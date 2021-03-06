/*
 
 FormatPaneController.swift
 
 CotEditor
 https://coteditor.com
 
 Created by 1024jp on 2014-04-18.
 
 ------------------------------------------------------------------------------
 
 © 2004-2007 nakamuxu
 © 2014-2016 1024jp
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 
 */

import Cocoa
import AudioToolbox

/// keys for styles controller
private enum StyleKey: String {
    case name
    case state
}

private let IsUTF8WithBOM = "UTF-8 with BOM"


final class FormatPaneController: NSViewController, NSTableViewDelegate {

    // MARK: Private Properties
    
    @IBOutlet private weak var inOpenEncodingMenu: NSPopUpButton?
    @IBOutlet private weak var inNewEncodingMenu: NSPopUpButton?
    
    @IBOutlet private weak var stylesController: NSArrayController?
    @IBOutlet private weak var syntaxTableView: NSTableView?
    @IBOutlet private weak var syntaxTableMenu: NSMenu?
    @IBOutlet private weak var syntaxStylesDefaultPopup: NSPopUpButton?
    @IBOutlet private weak var syntaxStyleDeleteButton: NSButton?
    
    
    
    // MARK:
    // MARK: Lifecycle
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    
    override var nibName: String? {
        
        return "FormatPane"
    }
    
    
    
    // MARK: View Controller Methods
    
    // setup UI
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.syntaxTableView?.doubleAction = #selector(openSyntaxEditSheet)
        self.syntaxTableView?.target = self
        
        self.setupEncodingMenus()
        self.setupSyntaxStyleMenus()
        
        NotificationCenter.default.addObserver(self, selector: #selector(setupEncodingMenus), name: .EncodingListDidUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setupSyntaxStyleMenus), name: .SyntaxListDidUpdate, object: nil)
    }
    
    
    /// apply current state to menu items
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        
        let isContextualMenu = (menuItem.menu == self.syntaxTableMenu)
        
        let representedStyleName: String? = {
            guard isContextualMenu else {
                return self.selectedStyleName
            }
            
            let clickedRow = self.syntaxTableView?.clickedRow ?? -1
            
            guard clickedRow != -1 else { return nil }  // clicked blank area
            
            guard let arrangedObjects = self.stylesController!.arrangedObjects as? [[String: Any]] else { return nil }
            
            return arrangedObjects[clickedRow][StyleKey.name.rawValue] as? String
        }()
        
        // set style name as representedObject to menu items whose action is related to syntax style
        if NSStringFromSelector(menuItem.action!).contains("Syntax") {
            menuItem.representedObject = representedStyleName
        }
        
        var isBundled = false
        var isCustomized = false
        if let representedStyleName = representedStyleName {
            isBundled = SyntaxManager.shared.isBundledSetting(name: representedStyleName)
            isCustomized = SyntaxManager.shared.isCustomizedBundledSetting(name: representedStyleName)
        }
        
        guard let action = menuItem.action else { return false }
        
        // append targeet style name to menu titles
        switch action {
        case #selector(openSyntaxMappingConflictSheet(_:)):
            return SyntaxManager.shared.existsMappingConflict
            
        case #selector(openSyntaxEditSheet(_:)) where SyntaxEditSheetMode(rawValue: menuItem.tag) == .copy:
            if !isContextualMenu {
                menuItem.title = String(format: NSLocalizedString("Duplicate “%@”", comment: ""), representedStyleName!)
            }
            menuItem.isHidden = (representedStyleName == nil)
            
        case #selector(deleteSyntaxStyle(_:)):
            menuItem.isHidden = (isBundled || representedStyleName == nil)
            
        case #selector(restoreSyntaxStyle(_:)):
            if !isContextualMenu {
                menuItem.title = String(format: NSLocalizedString("Restore “%@”", comment: ""), representedStyleName!)
            }
            menuItem.isHidden = (!isBundled || representedStyleName == nil)
            return isCustomized
            
        case #selector(exportSyntaxStyle(_:)):
            if !isContextualMenu {
                menuItem.title = String(format: NSLocalizedString("Export “%@”…", comment: ""), representedStyleName!)
            }
            menuItem.isHidden = (representedStyleName == nil)
            return (!isBundled || isCustomized)
            
        case #selector(revealSyntaxStyleInFinder(_:)):
            if !isContextualMenu {
                menuItem.title = String(format: NSLocalizedString("Reveal “%@” in Finder", comment: ""), representedStyleName!)
            }
            return (!isBundled || isCustomized)
            
        default: break
        }
        
        return true
    }
        
    
    
    
    // MARK: Delegate
    
    /// selected syntax style in "Installed styles" list table did change
    func tableViewSelectionDidChange(_ notification: Notification) {
        
        guard let object = notification.object as? NSTableView, object == self.syntaxTableView else { return }
        
        self.validateRemoveSyntaxStyleButton()
    }
    
    
    /// set action on swiping style name
    @available(macOS 10.11, *)
    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableRowActionEdge) -> [NSTableViewRowAction] {
        
        guard edge == .trailing else { return [] }
        
        // get swiped style
        let arrangedObjects = self.stylesController!.arrangedObjects as! [[String: Any]]
        let styleName = arrangedObjects[row][StyleKey.name.rawValue] as! String
        
        // check whether style is deletable
        let isBundled = SyntaxManager.shared.isBundledSetting(name: styleName)
        let isCustomized = SyntaxManager.shared.isCustomizedBundledSetting(name: styleName)
        
        // do nothing on undeletable style
        guard !isBundled || isCustomized else { return [] }
        
        if isCustomized {
            // Restore
            return [NSTableViewRowAction(style: .regular,
                                         title: NSLocalizedString("Restore", comment: ""),
                                         handler: { [weak self] (action: NSTableViewRowAction, row: Int) in
                                            self?.restoreSyntaxStyle(name: styleName)
                                            
                                            // finish swiped mode anyway
                                            tableView.rowActionsVisible = false
                })]
            
        } else {
            // Delete
            return [NSTableViewRowAction(style: .destructive,
                                         title: NSLocalizedString("Delete", comment: ""),
                                         handler: { [weak self] (action: NSTableViewRowAction, row: Int) in
                                            self?.deleteSyntaxStyle(name: styleName)
                })]
        }
    }
    
    
    
    // MARK: Action Messages
    
    /// save also availability of UTF-8 BOM
    @IBAction func changeEncodingInNewDocument(_ sender: Any?) {
        
        let withUTF8BOM = (self.inNewEncodingMenu?.selectedItem?.representedObject as? String) == IsUTF8WithBOM
        
        Defaults[.saveUTF8BOM] = withUTF8BOM
    }
    
    
    /// recommend user to use "Auto-Detect" on changing encoding setting
    @IBAction func checkSelectedItemOfInOpenEncodingMenu(_ sender: Any?) {
        
        guard let newTitle = self.inOpenEncodingMenu?.selectedItem?.title, newTitle != NSLocalizedString("Auto-Detect", comment: "") else { return }
        
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Are you sure you want to change to “%@”?", comment: ""), newTitle)
        alert.informativeText = NSLocalizedString("The default “Auto-Detect” is recommended for most cases.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Revert to “Auto-Detect”", comment: ""))
        alert.addButton(withTitle: String(format: NSLocalizedString("Change to “%@”", comment: ""), newTitle))
        
        alert.beginSheetModal(for: self.view.window!) { (returnCode: NSModalResponse) in
            
            guard returnCode == NSAlertFirstButtonReturn else { return }
            
            Defaults[.encodingInOpen] = String.Encoding.autoDetection.rawValue
        }
    }
    
    
    /// show encoding list edit sheet
    @IBAction func openEncodingEditSheet(_ sender: Any?) {
        
        self.presentViewControllerAsSheet(EncodingListViewController())
    }
    
    
    /// show syntax mapping conflict error sheet
    @IBAction func openSyntaxMappingConflictSheet(_ sender: Any?) {
        
        self.presentViewControllerAsSheet(SyntaxMappingConflictsViewController())
    }
    
    
    /// show syntax style edit sheet
    @IBAction func openSyntaxEditSheet(_ sender: AnyObject?) {
        
        let styleName = self.targetStyleName(for: sender)
        let mode = SyntaxEditSheetMode(rawValue: sender?.tag ?? 0) ?? .edit
        
        guard let viewController = SyntaxEditViewController(style: styleName, mode: mode) else { return }
        
        self.presentViewControllerAsSheet(viewController)
    }
    
    
    /// delete selected syntax style
    @IBAction func deleteSyntaxStyle(_ sender: Any?) {
        
        let styleName = self.targetStyleName(for: sender)
        
        self.deleteSyntaxStyle(name: styleName)
    }
    
    
    /// restore selected syntax style to original bundled one
    @IBAction func restoreSyntaxStyle(_ sender: Any?) {
        
        let styleName = self.targetStyleName(for: sender)
        
        self.restoreSyntaxStyle(name: styleName)
    }
    
    
    /// export selected syntax style
    @IBAction func exportSyntaxStyle(_ sender: Any?) {
        
        let styleName = self.targetStyleName(for: sender)
        
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.canSelectHiddenExtension = true
        savePanel.nameFieldLabel = NSLocalizedString("Export As:", comment: "")
        savePanel.nameFieldStringValue = styleName
        savePanel.allowedFileTypes = [SyntaxManager.shared.filePathExtension]
        
        savePanel.beginSheetModal(for: self.view.window!) { (result: Int) in
            guard result == NSFileHandlingPanelOKButton else { return }
            
            try? SyntaxManager.shared.exportSetting(name: styleName, to: savePanel.url!)
        }
    }
    
    
    /// import syntax style file via open panel
    @IBAction func importSyntaxStyle(_ sender: Any?) {
        
        let openPanel = NSOpenPanel()
        openPanel.prompt = NSLocalizedString("", comment: "")
        openPanel.resolvesAliases = true
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.allowedFileTypes = [SyntaxManager.shared.filePathExtension, "plist"]
        
        openPanel.beginSheetModal(for: self.view.window!) { [weak self] (result: Int) in
            guard result == NSFileHandlingPanelOKButton else { return }
            
            self?.importSyntaxStyle(fileURL: openPanel.url!)
        }
    }
    
    
    /// open directory in Application Support in Finder where the selected style exists
    @IBAction func revealSyntaxStyleInFinder(_ sender: Any?) {
        
        let styleName = self.targetStyleName(for: sender)
        
        guard let url = SyntaxManager.shared.urlForUserSetting(name: styleName) else { return }
        
        NSWorkspace.shared().activateFileViewerSelecting([url])
    }
    
    
    
    // MARK: Private Methods
    
    /// build encodings menus
    func setupEncodingMenus() {
        
        guard let inOpenMenu = self.inOpenEncodingMenu?.menu,
            let inNewMenu = self.inNewEncodingMenu?.menu else { return }
        
        let menuItems = EncodingManager.shared.encodingMenuItems
        
        inOpenMenu.removeAllItems()
        inNewMenu.removeAllItems()
        
        let autoDetectItem = NSMenuItem(title: NSLocalizedString("Auto-Detect", comment: ""), action: nil, keyEquivalent: "")
        autoDetectItem.tag = Int(String.Encoding.autoDetection.rawValue)
        inOpenMenu.addItem(autoDetectItem)
        inOpenMenu.addItem(NSMenuItem.separator())
        
        let UTF8Int = Int(String.Encoding.utf8.rawValue)
        for item in menuItems {
            inOpenMenu.addItem(item.copy() as! NSMenuItem)
            inNewMenu.addItem(item.copy() as! NSMenuItem)
            
            // add "UTF-8 with BOM" item only to "In New" menu
            if item.tag == UTF8Int {
                let bomItem = NSMenuItem(title: String.localizedNameOfUTF8EncodingWithBOM, action: nil, keyEquivalent: "")
                bomItem.tag = UTF8Int
                bomItem.representedObject = IsUTF8WithBOM
                inNewMenu.addItem(bomItem)
            }
        }
        
        // select menu item for the current setting manually although Cocoa-Bindings are used on these menus
        //   -> Because items were actually added after Cocoa-Binding selected the item.
        let inOpenEncoding = Defaults[.encodingInOpen]
        let inNewEncoding = Defaults[.encodingInNew]
        self.inOpenEncodingMenu?.selectItem(withTag: Int(inOpenEncoding))
        
        if Int(inNewEncoding) == UTF8Int {
            let UTF8WithBomIndex = inNewMenu.indexOfItem(withRepresentedObject: IsUTF8WithBOM)
            let index = Defaults[.saveUTF8BOM] ? UTF8WithBomIndex : UTF8WithBomIndex - 1
            // -> The normal "UTF-8" is just above "UTF-8 with BOM".
            
            self.inNewEncodingMenu?.selectItem(at: index)
        } else {
            self.inNewEncodingMenu?.selectItem(withTag: Int(inNewEncoding))
        }
    }
    
    
    /// build sytnax style menus
    func setupSyntaxStyleMenus() {
        
        let styleNames = SyntaxManager.shared.styleNames
        
        let styleStates: [[String: Any]] = styleNames.map { styleName in
            let isBundled = SyntaxManager.shared.isBundledSetting(name: styleName)
            let isCustomized = SyntaxManager.shared.isCustomizedBundledSetting(name: styleName)
            
            return [StyleKey.name.rawValue: styleName,
                    StyleKey.state.rawValue: (!isBundled || isCustomized)]
        }
        
        // update installed style list table
        self.stylesController?.content = styleStates
        self.validateRemoveSyntaxStyleButton()
        self.syntaxTableView?.reloadData()
        
        // update default style popup menu
        if let popup = self.syntaxStylesDefaultPopup {
            popup.removeAllItems()
            popup.addItem(withTitle: BundledStyleName.none)
            popup.menu?.addItem(NSMenuItem.separator())
            popup.addItems(withTitles: styleNames)
            
            // select menu item for the current setting manually although Cocoa-Bindings are used on this menu
            //   -> Because items were actually added after Cocoa-Binding selected the item.
            let defaultStyle = Defaults[.syntaxStyle]!
            let selectedStyle = styleNames.contains(defaultStyle) ? defaultStyle : BundledStyleName.none
            
            popup.selectItem(withTitle: selectedStyle)
        }
    }
    
    
    /// return syntax style name which is currently selected in the list table
    private dynamic var selectedStyleName: String {
        
        guard let styleInfo = self.stylesController?.selectedObjects.first as? [String: Any] else {
            return Defaults[.syntaxStyle]!
        }
        return styleInfo[StyleKey.name.rawValue] as! String
    }
    
    
    /// return representedObject if sender is menu item, otherwise selection in the list table
    private func targetStyleName(for sender: Any?) -> String {
        
        if let menuItem = sender as? NSMenuItem {
            return menuItem.representedObject as! String
        }
        return self.selectedStyleName
    }
    
    
    /// update button that deletes syntax style
    private func validateRemoveSyntaxStyleButton() {
        
        self.syntaxStyleDeleteButton?.isEnabled = !SyntaxManager.shared.isBundledSetting(name: self.selectedStyleName)
    }
    
    
    /// try to delete given syntax style
    private func deleteSyntaxStyle(name: String) {
        
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Are you sure you want to delete “%@” syntax style?", comment: ""), name)
        alert.informativeText = NSLocalizedString("This action cannot be undone.", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Delete", comment: ""))
        
        let window = self.view.window!
        alert.beginSheetModal(for: window) { [weak self] (returnCode: NSModalResponse) in
            
            guard returnCode == NSAlertSecondButtonReturn else {  // cancelled
                // flush swipe action for in case if this deletion was invoked by swiping the style name
                if #available(macOS 10.11, *) {
                    self?.syntaxTableView?.rowActionsVisible = false
                }
                return
            }
            
            do {
                try SyntaxManager.shared.removeSetting(name: name)
                
            } catch let error {
                alert.window.orderOut(nil)
                NSBeep()
                NSAlert(error: error).beginSheetModal(for: window)
                return
            }
            
            AudioServicesPlaySystemSound(.moveToTrash)
        }
    }
    
    
    /// try to restore given syntax style
    private func restoreSyntaxStyle(name: String) {
        
        do {
            try SyntaxManager.shared.restoreSetting(name: name)
        } catch let error {
            self.presentError(error)
        }
    }
    
    
    /// try to import syntax style file at given URL
    private func importSyntaxStyle(fileURL: URL) {
        
        do {
            try SyntaxManager.shared.importSetting(fileURL: fileURL)
        } catch let error {
            // ask for overwriting if a setting with the same name already exists
            self.presentError(error)
        }
    }
}
