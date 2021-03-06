/*
 
 StatusBarController.swift
 
 CotEditor
 https://coteditor.com
 
 Created by 1024jp on 2014-07-11.
 
 ------------------------------------------------------------------------------
 
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

final class StatusBarController: NSViewController {
    
    // MARK: Private Properties
    
    private let byteCountFormatter = ByteCountFormatter()
    private dynamic var editorStatus: NSAttributedString?
    private dynamic var documentStatus: NSAttributedString?
    private dynamic var showsReadOnly = false
    
    
    
    // MARK: 
    // MARK: Lifecycle
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        for key in type(of: self).observedDefaultKeys {
            UserDefaults.standard.removeObserver(self, forKeyPath: key.rawValue)
        }
    }
    
    
    
    // MARK: View Controller Methods
    
    /// setup
    override func viewDidLoad() {
        
        super.viewDidLoad()
        
        self.byteCountFormatter.isAdaptive = false
        
        // observe change of defaults
        for key in type(of: self).observedDefaultKeys {
            UserDefaults.standard.addObserver(self, forKeyPath: key.rawValue, context: nil)
        }
    }
    
    
    /// request analyzer to update editor info
    override func viewWillAppear() {
        
        super.viewWillAppear()
        
        self.documentAnalyzer?.needsUpdateStatusEditorInfo = true
    }
    
    
    /// request analyzer to stop updating editor info
    override func viewDidAppear() {
        
        super.viewDidAppear()
        
        self.documentAnalyzer?.needsUpdateStatusEditorInfo = false
    }
    
    
    // MARK: KVO
    
    /// apply change of user setting
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        if type(of: self).observedDefaultKeys.contains(where: { $0.rawValue == keyPath }) {
            self.updateEditorStatus()
            self.updateDocumentStatus()
        }
    }
    
    
    
    // MARK: Public Methods
    
    weak var documentAnalyzer: DocumentAnalyzer?
        {
        willSet {
            self.documentAnalyzer?.needsUpdateStatusEditorInfo = false
            NotificationCenter.default.removeObserver(self)
        }
        didSet {
            guard let analyzer = documentAnalyzer else { return }
            
            analyzer.needsUpdateStatusEditorInfo = !self.view.isHidden
            
            NotificationCenter.default.addObserver(self, selector: #selector(updateEditorStatus),
                                                   name: .AnalyzerDidUpdateEditorInfo, object: analyzer)
            NotificationCenter.default.addObserver(self, selector: #selector(updateDocumentStatus),
                                                   name: .AnalyzerDidUpdateFileInfo, object: analyzer)
            NotificationCenter.default.addObserver(self, selector: #selector(updateDocumentStatus),
                                                   name: .AnalyzerDidUpdateModeInfo, object: analyzer)
            
            self.updateEditorStatus()
            self.updateDocumentStatus()
        }
    }
    
    
    
    // MARK: Private Methods
    
    /// default keys to observe update
    private static let observedDefaultKeys: [DefaultKeys] = [.showStatusBarLines,
                                                             .showStatusBarChars,
                                                             .showStatusBarLength,
                                                             .showStatusBarWords,
                                                             .showStatusBarLocation,
                                                             .showStatusBarLine,
                                                             .showStatusBarColumn,
                                                             
                                                             .showStatusBarEncoding,
                                                             .showStatusBarLineEndings,
                                                             .showStatusBarFileSize,
                                                             ]
    
    
    /// update left side text
    func updateEditorStatus() {
        
        guard !self.view.isHidden else { return }
        guard let info = self.documentAnalyzer else { return }
        
        let status = NSMutableAttributedString()
        
        if Defaults[.showStatusBarLines] {
            status.appendFormattedState(value: info.lines, label: "Lines")
        }
        if Defaults[.showStatusBarChars] {
            status.appendFormattedState(value: info.chars, label: "Chars")
        }
        if Defaults[.showStatusBarLength] {
            status.appendFormattedState(value: info.length, label: "Length")
        }
        if Defaults[.showStatusBarWords] {
            status.appendFormattedState(value: info.words, label: "Words")
        }
        if Defaults[.showStatusBarLocation] {
            status.appendFormattedState(value: info.location, label: "Location")
        }
        if Defaults[.showStatusBarLine] {
            status.appendFormattedState(value: info.line, label: "Line")
        }
        if Defaults[.showStatusBarColumn] {
            status.appendFormattedState(value: info.column, label: "Column")
        }
        
        self.editorStatus = status
    }
    
    
    /// update right side text and readonly icon state
    func updateDocumentStatus() {
        
        guard !self.view.isHidden else { return }
        guard let info = self.documentAnalyzer else { return }
        
        let status = NSMutableAttributedString()
        
        if Defaults[.showStatusBarEncoding] {
            status.appendFormattedState(value: info.charsetName, label: nil)
        }
        if Defaults[.showStatusBarLineEndings] {
            status.appendFormattedState(value: info.lineEndings, label: nil)
        }
        if Defaults[.showStatusBarFileSize] {
            let fileSize = self.byteCountFormatter.string(for: info.fileSize)
            status.appendFormattedState(value: fileSize, label: nil)
        }
        
        self.documentStatus = status
        self.showsReadOnly = info.isReadOnly
    }
    
}



// MARK:

private extension NSMutableAttributedString {
    
    /// append formatted state
    func appendFormattedState(value: String?, label: String?) {
        
        if !self.string.isEmpty {
            self.append(NSAttributedString(string: "   "))
        }
        
        if let label = label {
            let localizedLabel = String(format: NSLocalizedString("%@: ", comment: ""),
                                        NSLocalizedString(label, comment: ""))
            let attrLabel = NSAttributedString(string: localizedLabel,
                                               attributes: [NSForegroundColorAttributeName: NSColor.labelColor])
            self.append(attrLabel)
        }
        
        let attrValue: NSAttributedString = {
            if let value = value {
                return NSAttributedString(string: value)
            } else {
                return NSAttributedString(string: "-",
                                          attributes: [NSForegroundColorAttributeName: NSColor.disabledControlTextColor])
            }
        }()
        
        self.append(attrValue)
    }
    
}
