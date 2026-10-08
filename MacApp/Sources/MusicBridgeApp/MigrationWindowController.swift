import AppKit

/// Presents the text exported by GoMusic and leaves the actual playlist
/// migration to the user's chosen service.  There is intentionally no attempt
/// to click through TuneMyMusic on the user's behalf.
@MainActor
final class MigrationWindowController: NSWindowController {
    private let playlist: PlaylistExport
    private let sourceURL: String
    private let textView = NSTextView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    private let tuneMyMusicURL = URL(string: "https://www.tunemymusic.com/zh-CN/transfer")!

    init(export: PlaylistExport, sourceURL: String) {
        self.playlist = export
        self.sourceURL = sourceURL

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "歌单已导出"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildInterface()
        window.contentMinSize = NSSize(width: 640, height: 420)
        window.setContentSize(NSSize(width: 760, height: 540))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows the exported list, copies it, and opens TuneMyMusic once.
    func presentForMigration() {
        window?.setContentSize(NSSize(width: 760, height: 540))
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        copyPlaylist(nil)
        openTuneMyMusic(nil)
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let title = NSTextField(labelWithString: "歌单文字已经准备好")
        title.font = .systemFont(ofSize: 22, weight: .semibold)

        let detail = NSTextField(wrappingLabelWithString: "已从源链接导出 \(playlist.count) 首歌曲。文本已复制到剪贴板；TuneMyMusic 的收藏迁移是可选步骤，请在网页中选择导入文本并按页面提示完成迁移。")
        detail.textColor = .secondaryLabelColor

        let source = NSTextField(wrappingLabelWithString: "源链接：\(sourceURL)")
        source.textColor = .tertiaryLabelColor
        source.font = .systemFont(ofSize: 11)

        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.string = playlist.text
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.frame = NSRect(x: 0, y: 0, width: 700, height: 260)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping

        let copyButton = NSButton(title: "复制歌单文本", target: self, action: #selector(copyPlaylist(_:)))
        copyButton.bezelStyle = .rounded

        let openButton = NSButton(title: "打开 TuneMyMusic", target: self, action: #selector(openTuneMyMusic(_:)))
        openButton.bezelStyle = .rounded
        openButton.keyEquivalent = "o"

        let closeButton = NSButton(title: "稍后处理", target: self, action: #selector(closeWindow(_:)))
        closeButton.bezelStyle = .rounded

        let buttonStack = NSStackView(views: [copyButton, openButton, closeButton])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 10

        let stack = NSStackView(views: [title, detail, source, scrollView, statusLabel, buttonStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22),
            title.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor),
            source.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 250),
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    @objc private func copyPlaylist(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(playlist.text, forType: .string)
        statusLabel.stringValue = "已复制 \(playlist.count) 首歌曲。你可以在 TuneMyMusic 中选择文本导入。"
    }

    @objc private func openTuneMyMusic(_ sender: Any?) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(tuneMyMusicURL, configuration: configuration) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error {
                    self?.statusLabel.stringValue = "无法打开 TuneMyMusic（\(error.localizedDescription)）。歌单文本已复制，请手动访问 https://www.tunemymusic.com/zh-CN/transfer。"
                } else {
                    self?.statusLabel.stringValue = "已打开 TuneMyMusic。收藏迁移是可选步骤；请在网页中粘贴刚复制的歌单文本。"
                }
            }
        }
    }

    @objc private func closeWindow(_ sender: Any?) {
        close()
    }
}
