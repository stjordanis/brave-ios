// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import Static
import Shared
import WebKit
import SnapKit
import Fuzi
import Storage
import Data

private let log = Logger.browserLogger

// MARK: - SearchCustomEngineViewController

class SearchCustomEngineViewController: UIViewController {
    
    // MARK: AddButtonType
    
    private enum AddButtonType {
        case enabled
        case disabled
        case loading
    }
    
    // MARK: Section
    
    private enum Section: Int, CaseIterable {
        case url
        case title
    }
    
    // MARK: Constants
    
    struct Constants {
        static let textInputRowIdentifier = "textInputRowIdentifier"
        static let urlInputRowIdentifier = "urlInputRowIdentifier"
        static let titleInputRowIdentifier = "titleInputRowIdentifier"
        static let searchEngineHeaderIdentifier = "searchEngineHeaderIdentifier"
        static let urlEntryMaxCharacterCount  = 150
        static let titleEntryMaxCharacterCount = 50
    }
    
    // MARK: Properties
    
    private var profile: Profile
        
    private var urlText: String?
    
    private var titleText: String?
    
    private var host: URL? {
        didSet {
            if let host = host, oldValue != host {
                fetchSearchEngineSupportForHost(host)
            }
        }
    }
    
    private var openSearchEngine: OpenSearchReference? {
        didSet {
            checkSupportAutoAddSearchEngine()
        }
    }
    
    private var isAutoAddEnabled = false
    
    private var dataTask: URLSessionDataTask? {
        didSet {
            oldValue?.cancel()
        }
    }
    
    private var fetcher: FaviconFetcher?
    
    fileprivate var faviconImage: UIImage?
    
    private lazy var spinnerView = UIActivityIndicatorView(style: .gray).then {
        $0.hidesWhenStopped = true
    }
    
    private var tableView = UITableView(frame: .zero, style: .grouped)
    
    // MARK: Lifecycle
    
    init(profile: Profile) {
        self.profile = profile
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Strings.CustomSearchEngine.customEngineNavigationTitle
        
        setup()
        doLayout()
        changeAddButton(for: .disabled)
    }
    
    // MARK: Internal
    
    private func setup() {
        tableView.do {
            $0.register(URLInputTableViewCell.self, forCellReuseIdentifier: Constants.urlInputRowIdentifier)
            $0.register(TitleInputTableViewCell.self, forCellReuseIdentifier: Constants.titleInputRowIdentifier)
            $0.register(SearchEngineTableViewHeader.self, forHeaderFooterViewReuseIdentifier: Constants.searchEngineHeaderIdentifier)
            $0.dataSource = self
            $0.delegate = self
        }
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: Strings.cancelButtonTitle, style: .plain, target: self, action: #selector(cancel))
    }
    
    private func doLayout() {
        view.addSubview(tableView)
        
        tableView.snp.makeConstraints { make in
            make.edges.equalTo(self.view)
        }
    }
    
    private func changeAddButton(for type: AddButtonType) {
        ensureMainThread {
            switch type {
                case .enabled:
                    self.navigationItem.rightBarButtonItem = UIBarButtonItem(
                        title: Strings.CustomSearchEngine.customEngineAddButtonTitle, style: .done, target: self, action: #selector(self.checkAddEngineType))
                    self.spinnerView.stopAnimating()
                case .disabled:
                    self.navigationItem.rightBarButtonItem = UIBarButtonItem(
                        title: Strings.CustomSearchEngine.customEngineAddButtonTitle, style: .done, target: self, action: #selector(self.checkAddEngineType))
                    self.navigationItem.rightBarButtonItem?.isEnabled = false
                    self.spinnerView.stopAnimating()
                    self.isAutoAddEnabled = false
                case .loading:
                    self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: self.spinnerView)
                    self.spinnerView.startAnimating()
            }
        }
    }
    
    private func handleError(error: Error) {
        let alert: UIAlertController
        
        if let searchError = error as? SearchEngineError {
            switch searchError {
                case .duplicate:
                    alert = ThirdPartySearchAlerts.duplicateCustomEngine()
                case .invalidQuery:
                    alert = ThirdPartySearchAlerts.incorrectCustomEngineForm()
                case .failedToSave:
                    alert = ThirdPartySearchAlerts.failedToAddThirdPartySearch()
                case .missingInformation:
                    alert = ThirdPartySearchAlerts.missingInfoToAddThirdPartySearch()
            }
        } else {
            alert = ThirdPartySearchAlerts.failedToAddThirdPartySearch()
        }
        
        log.error(error)
        present(alert, animated: true, completion: nil)
    }

    // MARK: Actions
    
    @objc func checkAddEngineType(_ nav: UINavigationController?) {
        if isAutoAddEnabled {
            addOpenSearchEngine()
        } else {
            addCustomSearchEngine()
        }
    }
    
    func addCustomSearchEngine() {
        view.endEditing(true)
        
        guard let title = titleText,
              let urlQuery = urlText,
              !title.isEmpty,
              !urlQuery.isEmpty else {
            present(ThirdPartySearchAlerts.missingInfoToAddThirdPartySearch(), animated: true, completion: nil)
            return
        }
        
        changeAddButton(for: .disabled)
        addSearchEngine(with: urlQuery, title: title)
    }
    
    @objc func cancel() {
        navigationController?.popViewController(animated: true)
    }
}

// MARK: - UITableViewDelegate UITableViewDataSource

extension SearchCustomEngineViewController: UITableViewDelegate, UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
            case Section.url.rawValue:
                guard let cell =
                        tableView.dequeueReusableCell(withIdentifier: Constants.urlInputRowIdentifier) as? URLInputTableViewCell else {
                    return UITableViewCell()
                }
                
                cell.delegate = self
                return cell
            default:
                guard let cell =
                        tableView.dequeueReusableCell(withIdentifier: Constants.titleInputRowIdentifier) as? TitleInputTableViewCell else {
                    return UITableViewCell()
                }
                
                cell.delegate = self
                return cell
        }
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == Section.url.rawValue else { return nil }
        
        return Strings.CustomSearchEngine.customEngineAddDesription
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let headerView = tableView.dequeueReusableHeaderFooterView(
                withIdentifier: Constants.searchEngineHeaderIdentifier) as? SearchEngineTableViewHeader else {
            return nil
        }

        switch section {
            case Section.url.rawValue:
                headerView.titleLabel.text = Strings.URL
            default:
                headerView.titleLabel.text = Strings.title
        }
        
        return headerView
    }
}

// MARK: Auto Add Engine

extension SearchCustomEngineViewController {
    
    fileprivate func addOpenSearchEngine() {
        guard var referenceURLString = openSearchEngine?.reference,
              let title = openSearchEngine?.title,
              var referenceURL = URL(string: referenceURLString),
              let faviconImage = faviconImage,
              let hostURLString = host?.absoluteString else {
            let alert = ThirdPartySearchAlerts.failedToAddThirdPartySearch()
            present(alert, animated: true, completion: nil)
            return
        }
        
        while referenceURLString.hasPrefix("/") {
            referenceURLString.remove(at: referenceURLString.startIndex)
        }
        
        let constructedReferenceURLString = "\(hostURLString)/\(referenceURLString)"

        if referenceURL.host == nil, let constructedReferenceURL = URL(string: constructedReferenceURLString) {
            referenceURL = constructedReferenceURL
        }
            
        downloadOpenSearchXML(referenceURL, referenceURL: referenceURLString, title: title, iconImage: faviconImage)
    }
    
    func downloadOpenSearchXML(_ url: URL, referenceURL: String, title: String, iconImage: UIImage) {
        changeAddButton(for: .loading)
        view.endEditing(true)
        
        NetworkManager().downloadResource(with: url).uponQueue(.main) { [weak self] response in
            guard let self = self else { return }
            
            if let openSearchEngine = OpenSearchParser(pluginMode: true).parse(response.data, referenceURL: referenceURL, image: iconImage, isCustomEngine: true) {
                self.addSearchEngine(openSearchEngine)
            } else {
                let alert = ThirdPartySearchAlerts.failedToAddThirdPartySearch()
                
                self.present(alert, animated: true) {
                    self.changeAddButton(for: .disabled)
                }
            }
        }
    }
    
    func addSearchEngine(_ engine: OpenSearchEngine) {
        let alert = ThirdPartySearchAlerts.addThirdPartySearchEngine(engine) { [weak self] alertAction in
            guard let self = self else { return }
            
            if alertAction.style == .cancel {
                self.changeAddButton(for: .enabled)
                return
            }
            
            do {
                try self.profile.searchEngines.addSearchEngine(engine)
                self.cancel()
            } catch {
                self.handleError(error: SearchEngineError.failedToSave)
                
                self.changeAddButton(for: .disabled)
            }
        }

        self.present(alert, animated: true, completion: {})
    }
}

// MARK: Auto Add Meta Data

extension SearchCustomEngineViewController {
    
    func checkSupportAutoAddSearchEngine() {
        guard let openSearchEngine = openSearchEngine else {
            changeAddButton(for: .disabled)
            checkManualAddExists()

            faviconImage = nil
            
            return
        }
        
        let matches = profile.searchEngines.orderedEngines.filter {$0.referenceURL == openSearchEngine.reference}
        
        if !matches.isEmpty {
            changeAddButton(for: .disabled)
            checkManualAddExists()
        } else {
            changeAddButton(for: .enabled)
            isAutoAddEnabled = true
        }
    }
    
    func fetchSearchEngineSupportForHost(_ host: URL) {
        changeAddButton(for: .disabled)
        
        dataTask = URLSession.shared.dataTask(with: host) { [weak self] data, _, error in
            guard let data = data, error == nil else {
                self?.openSearchEngine = nil
                return
            }
            
            ensureMainThread {
                self?.loadSearchEngineMetaData(from: data, url: host)
            }
        }
        
        dataTask?.resume()
    }

    func loadSearchEngineMetaData(from data: Data, url: URL) {
        guard let root = try? HTMLDocument(data: data as Data),
            let searchEngineDetails = fetchOpenSearchReference(document: root) else {
            openSearchEngine = nil
            return
        }
                
        fetcher = FaviconFetcher(siteURL: url, kind: .favicon)
        
        fetcher?.load { [weak self] _, attributes in
            guard let self = self else { return }
            
            self.faviconImage = attributes.image ?? #imageLiteral(resourceName: "defaultFavicon")
            self.openSearchEngine = searchEngineDetails
        }
    }
    
    func fetchOpenSearchReference(document: HTMLDocument) -> OpenSearchReference? {
        let documentXpath = "//head//link[contains(@type, 'application/opensearchdescription+xml')]"
        
        for link in document.xpath(documentXpath) {
            if let referenceLink = link["href"], let title = link["title"] {
                return OpenSearchReference(reference: referenceLink, title: title)
            }
        }
        
        return nil
    }
}

// MARK: Manual Add Engine

extension SearchCustomEngineViewController {
    
    fileprivate func addSearchEngine(with urlQuery: String, title: String) {
        changeAddButton(for: .loading)

        let safeURLQuery = urlQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        createSearchEngine(using: safeURLQuery, name: safeTitle) { [weak self] engine, error in
            guard let self = self else { return }
            
            if let error = error {
                self.handleError(error: error)
                
                self.changeAddButton(for: .disabled)
            } else if let engine = engine {
                do {
                    try self.profile.searchEngines.addSearchEngine(engine)
                    self.cancel()
                } catch {
                    self.handleError(error: SearchEngineError.failedToSave)

                    self.changeAddButton(for: .enabled)
                }
            }
            
        }
    }
    
    private func createSearchEngine(using query: String, name: String, completion: @escaping ((OpenSearchEngine?, SearchEngineError?) -> Void)) {
        // Check Search Query is not valid
        guard let template = getSearchTemplate(with: query),
              let urlText = template.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
              let url = URL(string: urlText),
              url.isWebPage()  else {
            completion(nil, SearchEngineError.invalidQuery)
            return
        }
    
        // Check Engine Exists
        guard profile.searchEngines.orderedEngines.filter({ $0.shortName == name }).isEmpty else {
            completion(nil, SearchEngineError.duplicate)
            return
        }

        var engineImage = #imageLiteral(resourceName: "defaultFavicon")

        guard let hostUrl = host else {
            let engine = OpenSearchEngine(shortName: name, image: engineImage, searchTemplate: template, isCustomEngine: true)

            completion(engine, nil)
            return
        }

        fetcher = FaviconFetcher(siteURL: hostUrl, kind: .favicon)

        fetcher?.load { siteUrl, attributes in
            if let image = attributes.image {
                engineImage = image
            }

            let engine = OpenSearchEngine(shortName: name, image: engineImage, searchTemplate: template, isCustomEngine: true)

            completion(engine, nil)
        }
    }
    
    private func getSearchTemplate(with query: String) -> String? {
        let searchTermPlaceholder = "%s"
        let searchTemplatePlaceholder = "{searchTerms}"
        
        if query.contains(searchTermPlaceholder) {
            return query.replacingOccurrences(of: searchTermPlaceholder, with: searchTemplatePlaceholder)
        }
        
        return nil
    }
    
    private func checkManualAddExists() {
        guard let url = urlText, let title = titleText  else {
            return
        }
        
        if !url.isEmpty, !title.isEmpty {
            changeAddButton(for: .enabled)
        } else {
            changeAddButton(for: .disabled)
        }
    }
}

// MARK: - UITextViewDelegate

extension SearchCustomEngineViewController: UITextViewDelegate {
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard text.rangeOfCharacter(from: .newlines) == nil else {
            textView.resignFirstResponder()
            return false
        }

        return textView.text.count + (text.count - range.length) <= Constants.urlEntryMaxCharacterCount
    }
    
    func textViewDidChange(_ textView: UITextView) {
        changeAddButton(for: .disabled)
        
        urlText = textView.text

        if let text = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           let encodedText = text.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
           let url = URL(string: encodedText),
           url.host != nil,
           url.isWebPage() {
            if let scheme = url.scheme, let host = url.host {
                self.host = URL(string: "\(scheme)://\(host)")
            }
        }
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        urlText = textView.text
    }
}

// MARK: - UITextFieldDelegate

extension SearchCustomEngineViewController: UITextFieldDelegate {
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let text = textField.text, text.rangeOfCharacter(from: .newlines) == nil else { return false }
        
        let currentString = text as NSString
        let newString: NSString = currentString.replacingCharacters(in: range, with: string) as NSString
        
        let shouldChangeCharacters = newString.length <= Constants.titleEntryMaxCharacterCount
        
        if shouldChangeCharacters {
            titleText = newString as String
            checkManualAddExists()
        }
        
        return shouldChangeCharacters
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        titleText = textField.text
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.endEditing(true)
        
        return true
    }
}

// MARK: - SearchEngineTableViewHeader

fileprivate class SearchEngineTableViewHeader: UITableViewHeaderFooterView {
    
    // MARK: Design
    
    struct Design {
        static let headerHeight: CGFloat = 44
        static let headerInset: CGFloat = 20
    }
    
    // MARK: Properties
    
    var titleLabel = UILabel().then {
        $0.font = UIFont.systemFont(ofSize: 14)
        $0.textColor = UIColor.Photon.grey50
    }

    lazy var addEngineButton = OpenSearchEngineButton(
        title: Strings.CustomSearchEngine.customEngineAutoAddTitle,
        hidesWhenDisabled: false).then {
        $0.addTarget(self, action: #selector(addEngineAuto), for: .touchUpInside)
        $0.isHidden = true
    }

    var actionHandler: (() -> Void)?

    // MARK: Lifecycle
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        addSubview(titleLabel)
        addSubview(addEngineButton)
        
        setConstraints()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal
    
    func setConstraints() {
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(Design.headerInset)
            make.top.equalToSuperview()
            make.bottom.equalToSuperview()
            make.height.equalTo(Design.headerHeight)
        }
        
        addEngineButton.snp.makeConstraints { make in
            make.trailing.equalTo(snp.trailing).inset(Design.headerInset)
            make.centerY.equalToSuperview()
            make.height.equalTo(snp.height)
        }
    }
    
    // MARK: Actions

    @objc private func addEngineAuto() {
        actionHandler?()
    }
}

// MARK: URLInputTableViewCell

fileprivate class URLInputTableViewCell: UITableViewCell {

    // MARK: Design
    
    struct Design {
        static let cellHeight: CGFloat = 88
        static let cellInset: CGFloat = 16
    }
    
    // MARK: Properties
    
    var textview = UITextView(frame: .zero)
    
    weak var delegate: UITextViewDelegate? {
        didSet {
            textview.delegate = delegate
        }
    }
    // MARK: Lifecycle
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: Internal
    
    private func setup() {
        textview = UITextView(frame: CGRect(x: 0, y: 0, width: contentView.frame.width, height: contentView.frame.height)).then {
            $0.text = "https://"
            $0.backgroundColor = .clear
            $0.backgroundColor = .clear
            $0.font = UIFont.systemFont(ofSize: Design.cellInset)
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
            $0.spellCheckingType = .no
            $0.keyboardType = .URL
        }
        
        contentView.addSubview(textview)
        
        textview.snp.makeConstraints({ make in
            make.leading.trailing.equalToSuperview().inset(Design.cellInset)
            make.bottom.top.equalToSuperview()
            make.height.equalTo(Design.cellHeight)
        })
    }
}

// MARK: TitleInputTableViewCell

fileprivate class TitleInputTableViewCell: UITableViewCell {

    // MARK: Design
    
    struct Design {
        static let cellHeight: CGFloat = 44
        static let cellInset: CGFloat = 16
    }
    
    // MARK: Properties
    
    var textfield: UITextField = UITextField(frame: .zero)
    
    weak var delegate: UITextFieldDelegate? {
        didSet {
            textfield.delegate = delegate
        }
    }

    // MARK: Lifecycle
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: Internal
    
    private func setup() {
        textfield = UITextField(frame: CGRect(x: 0, y: 0, width: contentView.frame.width, height: contentView.frame.height))
                
        contentView.addSubview(textfield)
        
        textfield.snp.makeConstraints({ make in
            make.leading.trailing.equalToSuperview().inset(Design.cellInset)
            make.bottom.top.equalToSuperview()
            make.height.equalTo(Design.cellHeight)
        })
    }
}