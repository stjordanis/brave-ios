// Copyright 2020 The Brave Authors. All rights reserved.
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import UIKit
import PanModal
import Static
import Shared
import BraveUI

#if canImport(SwiftUI)
import SwiftUI
#endif

enum MenuButton: Int, CaseIterable {
    case vpn, settings, history, bookmarks, downloads, add, share
    
    var title: String {
        switch self {
        // This string should not be translated.
        case .vpn: return "Brave VPN"
        case .bookmarks: return Strings.bookmarksMenuItem
        case .history: return Strings.historyMenuItem
        case .settings: return Strings.settingsMenuItem
        case .add: return Strings.addToMenuItem
        case .share: return Strings.shareWithMenuItem
        case .downloads: return Strings.downloadsMenuItem
        }
    }
    
    var icon: UIImage {
        switch self {
        case .vpn: return #imageLiteral(resourceName: "vpn_menu_icon").template
        case .bookmarks: return #imageLiteral(resourceName: "menu_bookmarks").template
        case .history: return #imageLiteral(resourceName: "menu-history").template
        case .settings: return #imageLiteral(resourceName: "menu-settings").template
        case .add: return #imageLiteral(resourceName: "menu-add-bookmark").template
        case .share: return #imageLiteral(resourceName: "nav-share").template
        case .downloads: return #imageLiteral(resourceName: "menu-downloads").template
        }
    }
}

@available(iOS 13.0, *)
struct NewMenuView: View {
    var buttons: [MenuButton]
    var tappedButton: ((MenuButton) -> Void)?
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(buttons, id: \.self) { btn in
                    VStack(alignment: .leading, spacing: 0) {
                        Button(action: {
                            tappedButton?(btn)
                        }) {
                            HStack {
                                Image(uiImage: btn.icon)
                                    .frame(width: 32)
                                Text(verbatim: btn.title)
                                Spacer()
                            }
                            .padding()
                        }
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.clear)
        }
    }
}

@available(iOS 13.0, *)
class NewMenuHostingController: UIHostingController<NewMenuView>, PanModalPresentable {
    private weak var bvc: BrowserViewController?
    private func presentInnerMenu(_ viewController: UIViewController) {
        let container = NewMenuNavigationController(rootViewController: viewController)
        container.delegate = self
        container.modalPresentationStyle = .overCurrentContext
        container.dismissed = {
            self.panModalSetNeedsLayoutUpdate()
        }
        present(container, animated: true) {
            self.panModalSetNeedsLayoutUpdate()
        }
    }
    init(bvc: BrowserViewController) {
        self.bvc = bvc
        super.init(rootView: NewMenuView(buttons: MenuButton.allCases))
        
        rootView.tappedButton = { [unowned self] button in
            switch button {
            case .vpn:
                break
            case .bookmarks: openBookmarks()
            case .history: openHistory()
            case .settings: openSettings()
            case .add: openAddBookmark()
            case .share: openShareSheet()
            case .downloads: openDownloads()
            }
        }
    }
    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .clear
    }
    
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
        if let _ = presentedViewController {
            bvc?.dismiss(animated: flag, completion: completion)
        } else {
            super.dismiss(animated: flag, completion: completion)
        }
    }
    
    private func openBookmarks() {
        let vc = BookmarksViewController(folder: Bookmarkv2.lastVisitedFolder(), isPrivateBrowsing: PrivateBrowsingManager.shared.isPrivateBrowsing)
        vc.toolbarUrlActionsDelegate = bvc
        presentInnerMenu(vc)
    }
    
    private func openDownloads() {
        guard let bvc = bvc else { return }
        let vc = DownloadsPanel(profile: bvc.profile)
        let currentTheme = Theme.of(bvc.tabManager.selectedTab)
        vc.applyTheme(currentTheme)
        presentInnerMenu(vc)
    }
    
    private func openAddBookmark() {
        guard let bvc = bvc, let tab = bvc.tabManager.selectedTab, let url = tab.url else { return }
        
        let bookmarkUrl = url.decodeReaderModeURL ?? url
        
        let mode = BookmarkEditMode.addBookmark(title: tab.displayTitle, url: bookmarkUrl.absoluteString)
        
        let vc = AddEditBookmarkTableViewController(mode: mode)
        presentInnerMenu(vc)
        
    }
    
    private func openHistory() {
        guard let bvc = bvc else { return }
        let vc = HistoryViewController(isPrivateBrowsing: PrivateBrowsingManager.shared.isPrivateBrowsing)
        vc.toolbarUrlActionsDelegate = bvc
        presentInnerMenu(vc)
    }
    
    private func openSettings() {
        guard let bvc = bvc else { return }
        let vc = SettingsViewController(profile: bvc.profile, tabManager: bvc.tabManager, feedDataSource: bvc.feedDataSource, rewards: bvc.rewards, legacyWallet: bvc.legacyWallet)
        vc.settingsDelegate = bvc
        presentInnerMenu(vc)
    }
    
    private func openShareSheet() {
        guard let bvc = bvc else { return }
        dismiss(animated: true)
        bvc.tabToolbarDidPressShare()
    }
    
    var panScrollable: UIScrollView? {
        // in iOS 13, ScrollView will exist within a host view
        // in iOS 14, it will be a direct subview
        func _scrollViewChild(in parentView: UIView, depth: Int = 0) -> UIScrollView? {
            if depth > 2 { return nil }
            if let scrollView = parentView as? UIScrollView {
                return scrollView
            }
            for view in parentView.subviews {
                if let scrollView = view as? UIScrollView {
                    return scrollView
                }
                if !view.subviews.isEmpty, let childScrollView = _scrollViewChild(in: view, depth: depth + 1) {
                    return childScrollView
                }
            }
            return nil
        }
        if let vc = presentedViewController, !vc.isBeingPresented {
            if let nc = vc as? UINavigationController, let vc = nc.topViewController {
                let scrollView = _scrollViewChild(in: vc.view)
                return scrollView
            }
            let scrollView = _scrollViewChild(in: vc.view)
            return scrollView
        }
        view.layoutIfNeeded()
        return _scrollViewChild(in: view)
    }
    var longFormHeight: PanModalHeight {
        .maxHeight
    }
    var shortFormHeight: PanModalHeight {
        .contentHeight(320)
    }
    var allowsExtendedPanScrolling: Bool {
        true
    }
}

@available(iOS 13.0, *)
extension NewMenuHostingController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        panModalSetNeedsLayoutUpdate()
    }
}

class NewMenuNavigationController: UINavigationController {
    var dismissed: (() -> Void)?
    
    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        viewController.navigationItem.rightBarButtonItem = .init(barButtonSystemItem: .done, target: self, action: #selector(tappedDone))
        super.pushViewController(viewController, animated: animated)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Needed or else pan modal top scroll insets are messed up for some reason
        navigationBar.isTranslucent = false
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        dismissed?()
    }

    @objc private func tappedDone() {
        dismiss(animated: true) { [dismissed] in
            dismissed?()
        }
    }
}
