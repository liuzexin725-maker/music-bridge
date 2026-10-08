import AppKit

private final class FlippedContentView: NSView {
    override var isFlipped: Bool { true }
}

private enum InterfaceStyle {
    static let pageTitle = NSFont.systemFont(ofSize: 24, weight: .semibold)
    static let sectionTitle = NSFont.systemFont(ofSize: 18, weight: .semibold)
    static let prominentBody = NSFont.systemFont(ofSize: 15, weight: .semibold)
    static let body = NSFont.systemFont(ofSize: 13)
    static let bodyEmphasis = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let secondary = NSFont.systemFont(ofSize: 12)
    static let secondaryEmphasis = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let caption = NSFont.systemFont(ofSize: 11)
    static let captionEmphasis = NSFont.systemFont(ofSize: 11, weight: .medium)
    static let button = NSFont.systemFont(ofSize: 13, weight: .semibold)

    static let controlHeight: CGFloat = 32
    static let primaryButtonWidth: CGFloat = 112
    static let importButtonWidth: CGFloat = 132
}

private final class CardContainerView: NSView {
    enum Style {
        case card
        case status
    }

    private let style: Style
    private let radius: CGFloat

    init(
        contentView: NSView,
        style: Style,
        radius: CGFloat,
        horizontalMargin: CGFloat,
        verticalMargin: CGFloat
    ) {
        self.style = style
        self.radius = radius
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = true
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalMargin),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -horizontalMargin),
            contentView.topAnchor.constraint(equalTo: topAnchor, constant: verticalMargin),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -verticalMargin)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.cornerRadius = radius
        switch style {
        case .card:
            // Keep cards quiet like Apple's source-list and grid surfaces.
            // The hierarchy comes from spacing and native semantic colors.
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.28).cgColor
            layer?.borderColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
            layer?.shadowColor = NSColor.black.withAlphaComponent(0.24).cgColor
            layer?.shadowOpacity = 0.18
            layer?.shadowRadius = 10
            layer?.shadowOffset = CGSize(width: 0, height: -2)
        case .status:
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.24).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.12).cgColor
            layer?.borderWidth = 0.5
            layer?.shadowOpacity = 0
        }
    }
}

/// Uses the macOS 26/27 glass surface when available and falls back to the
/// native visual-effect material on older systems.
private final class GlassSurfaceView: NSView {
    init(
        contentView: NSView,
        cornerRadius: CGFloat,
        tintColor: NSColor? = nil,
        interactive: Bool,
        insets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.tintColor = tintColor
            glass.alphaValue = 0.92
            if #available(macOS 27.0, *) {
                glass.effectIsInteractive = interactive
            }
            glass.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glass)
            glass.contentView = contentContainer
            NSLayoutConstraint.activate([
                glass.leadingAnchor.constraint(equalTo: leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: trailingAnchor),
                glass.topAnchor.constraint(equalTo: topAnchor),
                glass.bottomAnchor.constraint(equalTo: bottomAnchor),
                contentContainer.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
                contentContainer.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
                contentContainer.topAnchor.constraint(equalTo: glass.topAnchor),
                contentContainer.bottomAnchor.constraint(equalTo: glass.bottomAnchor)
            ])
        } else {
            let visual = NSVisualEffectView()
            visual.material = .hudWindow
            visual.blendingMode = .withinWindow
            visual.state = .active
            visual.alphaValue = 0.86
            visual.wantsLayer = true
            visual.layer?.cornerRadius = cornerRadius
            visual.translatesAutoresizingMaskIntoConstraints = false
            addSubview(visual)
            visual.addSubview(contentContainer)
            NSLayoutConstraint.activate([
                visual.leadingAnchor.constraint(equalTo: leadingAnchor),
                visual.trailingAnchor.constraint(equalTo: trailingAnchor),
                visual.topAnchor.constraint(equalTo: topAnchor),
                visual.bottomAnchor.constraint(equalTo: bottomAnchor),
                contentContainer.leadingAnchor.constraint(equalTo: visual.leadingAnchor),
                contentContainer.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
                contentContainer.topAnchor.constraint(equalTo: visual.topAnchor),
                contentContainer.bottomAnchor.constraint(equalTo: visual.bottomAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: insets.left),
            contentView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor, constant: -insets.right),
            contentView.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: insets.top),
            contentView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: -insets.bottom)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Main window for the low-friction export flow and the optional manual
/// Apple Music download flow.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let goMusicClient = GoMusicClient()
    private let catalogClient = AppleMusicCatalogClient()
    private let downloaderRunner = DownloaderRunner()
    private let ipodImporter = IPodImporter()

    private let sourceURLField = NSTextField()
    private let startButton = NSButton(title: "开始", target: nil, action: nil)
    private let mainStatusIcon = NSImageView()
    private let mainStatusSpinner = NSProgressIndicator()
    private let mainStatusTitleLabel = NSTextField(labelWithString: "")
    private let mainStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let downloadProgressBar = NSProgressIndicator()
    private let downloadInfoLabel = NSTextField(labelWithString: "")

    private let advancedDisclosureButton = NSButton(title: "Apple Music 下载", target: nil, action: nil)
    private let advancedSummaryLabel = NSTextField(labelWithString: "出错时展开")
    private var advancedBox: NSView?
    private weak var advancedHeaderView: NSView?
    private var isAdvancedExpanded = false
    private let settingsDisclosureButton = NSButton(title: "连接", target: nil, action: nil)
    private let settingsContainer = NSView()
    private var isSettingsExpanded = false
    private let logDisclosureButton = NSButton(title: "日志", target: nil, action: nil)
    private var logScrollView: NSScrollView?
    private var isLogExpanded = false
    private weak var sidebarImportButton: NSButton?
    private weak var sidebarDownloadButton: NSButton?
    private weak var sidebarSettingsButton: NSButton?
    private weak var sidebarView: NSView?
    private weak var sidebarStackView: NSView?
    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var isCompactLayout = false

    private weak var devicePanel: NSView?
    private weak var deviceIconContainer: NSView?
    private weak var deviceIcon: NSImageView?
    private weak var deviceTitleLabel: NSTextField?
    private weak var deviceDetailLabel: NSTextField?
    private weak var deviceStatusLabel: NSTextField?
    private weak var deviceImportButton: NSButton?

    private let binaryPathField = NSTextField()
    private let workingDirectoryField = NSTextField()
    private let wrapperLauncherField = NSTextField()
    private let wrapperURLField = NSTextField()
    private let downloadStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let logView = NSTextView()

    private let workspaceTitleLabel = NSTextField(labelWithString: "Music Bridge")
    private let workspaceToolbarHint = NSTextField(labelWithString: "就绪")
    private weak var mainScrollView: NSScrollView?

    private var migrationWindowController: MigrationWindowController?
    private var progressTimer: Timer?
    private var downloadStartedAt: Date?
    private var workflowTask: Task<Void, Never>?
    private var isMatchingCatalog = false
    private var isDownloaderRunning = false
    private var isIPodImporting = false
    private var downloadSnapshot: [URL: FileSignature] = [:]
    private var pendingImportFiles: [(url: URL, root: URL)] = []
    private var mountObserver: NSObjectProtocol?
    private var unmountObserver: NSObjectProtocol?
    private var amdlPath = UserDefaults.standard.string(forKey: "amdlPath") ?? MainWindowController.discoveredPaths.amdl
    private var workingDirectory = UserDefaults.standard.string(forKey: "workingDirectory") ?? MainWindowController.discoveredPaths.directory
    private var wrapperLauncherPath = UserDefaults.standard.string(forKey: "wrapperLauncherPath") ?? MainWindowController.discoveredPaths.wrapper

    private static let discoveredPaths: (amdl: String, directory: String, wrapper: String?) = {
        let fileManager = FileManager.default
        var roots: [URL] = [URL(fileURLWithPath: fileManager.currentDirectoryPath)]
        var cursor = Bundle.main.bundleURL
        for _ in 0..<10 {
            roots.append(cursor)
            cursor.deleteLastPathComponent()
        }

        for root in roots {
            let binary = root.appendingPathComponent("amdl")
            let config = root.appendingPathComponent("config.yaml")
            guard fileManager.isExecutableFile(atPath: binary.path), fileManager.fileExists(atPath: config.path) else {
                continue
            }
            let wrapper = root.appendingPathComponent("work/wrapper-lite-macos/start-local.sh")
            return (binary.path, root.path, fileManager.isExecutableFile(atPath: wrapper.path) ? wrapper.path : nil)
        }
        return ("", "", nil)
    }()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Music Bridge"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isMovableByWindowBackground = true
        window.showsResizeIndicator = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentMinSize = NSSize(width: 820, height: 540)
        window.minSize = NSSize(width: 820, height: 580)
        super.init(window: window)
        window.delegate = self
        configureRunner()
        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshIPodPanel()
            }
        }
        unmountObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshIPodPanel()
            }
        }
        buildInterface()
        window.setContentSize(NSSize(width: 980, height: 640))
    }

    deinit {
        if let mountObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(mountObserver)
        }
        if let unmountObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(unmountObserver)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureRunner() {
        downloaderRunner.onOutput = { [weak self] line in
            guard let self else { return }
            self.updateDownloadProgress(from: line)
            if !self.isProgressOutput(line) {
                self.appendLog(line)
            }
        }
        downloaderRunner.onStarted = { [weak self] in
            guard let self else { return }
            self.isDownloaderRunning = true
            self.downloadStatusLabel.stringValue = "下载中"
            self.beginDownloadProgress()
            self.setPrimaryButtonToStop()
            self.setMainStatus(
                title: "正在下载音乐",
                detail: "正在处理歌曲",
                kind: .loading
            )
        }
        downloaderRunner.onFinished = { [weak self] status in
            guard let self else { return }
            self.isDownloaderRunning = false
            let previousSnapshot = self.downloadSnapshot
            self.downloadSnapshot.removeAll()
            self.endDownloadProgress()
            self.setPrimaryButtonToStart(title: status == 0 ? "开始" : "重试")
            if status == 0 {
                let workingURL = URL(fileURLWithPath: self.workingDirectory, isDirectory: true)
                let changed = self.ipodImporter.changedAudioFiles(
                    in: workingURL,
                    comparedTo: previousSnapshot
                )
                self.queuePendingIPodImport(changed)
            } else {
                self.downloadStatusLabel.stringValue = "下载进程已退出（代码 \(status)）。请查看运行日志后重试。"
                self.setAdvancedExpanded(true)
                self.setLogExpanded(true)
                self.setMainStatus(
                    title: "下载没有完成",
                    detail: "错误代码 \(status)，可重试",
                    kind: .failure
                )
            }
        }
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active
        background.alphaValue = 0.94
        background.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(background)

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(sidebar)
        sidebarView = sidebar

        let sidebarIcon = NSImageView(image: NSImage(
            systemSymbolName: "music.note.list",
            accessibilityDescription: "Music Bridge"
        ) ?? NSImage())
        sidebarIcon.contentTintColor = .controlAccentColor
        sidebarIcon.imageScaling = .scaleProportionallyUpOrDown
        sidebarIcon.translatesAutoresizingMaskIntoConstraints = false

        let sidebarTitle = NSTextField(labelWithString: "Music Bridge")
        sidebarTitle.font = InterfaceStyle.prominentBody

        let sidebarBrand = NSStackView(views: [sidebarIcon, sidebarTitle])
        sidebarBrand.orientation = .horizontal
        sidebarBrand.alignment = .centerY
        sidebarBrand.spacing = 9

        let workspaceLabel = NSTextField(labelWithString: "工作区")
        workspaceLabel.font = InterfaceStyle.captionEmphasis
        workspaceLabel.textColor = .tertiaryLabelColor

        let importButton = makeSidebarButton(
            title: "导入歌单",
            symbolName: "link",
            selected: true,
            action: #selector(selectImportFromSidebar(_:))
        )
        let downloadSidebarButton = makeSidebarButton(
            title: "Apple Music 下载",
            symbolName: "arrow.down.circle",
            selected: false,
            action: #selector(selectDownloadFromSidebar(_:))
        )

        let utilityLabel = NSTextField(labelWithString: "其他")
        utilityLabel.font = InterfaceStyle.captionEmphasis
        utilityLabel.textColor = .tertiaryLabelColor

        let settingsSidebarButton = makeSidebarButton(
            title: "连接设置",
            symbolName: "slider.horizontal.3",
            selected: false,
            action: #selector(selectSettingsFromSidebar(_:))
        )
        sidebarImportButton = importButton
        sidebarDownloadButton = downloadSidebarButton
        sidebarSettingsButton = settingsSidebarButton

        let sidebarHint = NSTextField(wrappingLabelWithString: "粘贴链接后，Music Bridge 会自动判断下一步。")
        sidebarHint.font = InterfaceStyle.caption
        sidebarHint.textColor = .tertiaryLabelColor
        sidebarHint.maximumNumberOfLines = 3

        let sidebarStack = NSStackView(views: [
            sidebarBrand,
            workspaceLabel,
            importButton,
            downloadSidebarButton,
            utilityLabel,
            settingsSidebarButton,
            NSView(),
            sidebarHint
        ])
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .leading
        sidebarStack.spacing = 7
        sidebarStack.setCustomSpacing(16, after: sidebarBrand)
        sidebarStack.setCustomSpacing(6, after: workspaceLabel)
        sidebarStack.setCustomSpacing(18, after: utilityLabel)
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarStack)
        sidebarStackView = sidebarStack

        workspaceTitleLabel.font = InterfaceStyle.prominentBody
        workspaceTitleLabel.textColor = .labelColor
        workspaceTitleLabel.alignment = .left

        workspaceToolbarHint.font = InterfaceStyle.secondary
        workspaceToolbarHint.textColor = .tertiaryLabelColor
        workspaceToolbarHint.alignment = .right

        let toolbarSpacer = NSView()
        toolbarSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let toolbarStack = NSStackView(views: [
            workspaceTitleLabel,
            toolbarSpacer,
            workspaceToolbarHint
        ])
        toolbarStack.orientation = .horizontal
        toolbarStack.alignment = .centerY
        toolbarStack.spacing = 10
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false

        let toolbar = GlassSurfaceView(
            contentView: toolbarStack,
            cornerRadius: 0,
            interactive: true,
            insets: NSEdgeInsets(top: 0, left: 26, bottom: 0, right: 20)
        )
        background.addSubview(toolbar)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(scrollView)
        mainScrollView = scrollView

        let documentView = FlippedContentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        documentView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scrollView.documentView = documentView

        let title = NSTextField(labelWithString: "粘贴歌单链接")
        title.font = InterfaceStyle.pageTitle
        title.alignment = .left
        title.maximumNumberOfLines = 1
        let header = title

        let devicePanel = makeIPodDevicePanel()
        self.devicePanel = devicePanel

        sourceURLField.placeholderString = "粘贴网易云或 Apple Music 歌单链接"
        configureTextField(sourceURLField, fontSize: InterfaceStyle.body.pointSize)
        sourceURLField.target = self
        sourceURLField.action = #selector(startOneClick(_:))
        sourceURLField.setAccessibilityLabel("源歌单链接")

        startButton.target = self
        startButton.action = #selector(startOneClick(_:))
        startButton.bezelStyle = .rounded
        startButton.controlSize = .large
        startButton.font = InterfaceStyle.button
        startButton.bezelColor = .controlAccentColor
        startButton.contentTintColor = .white
        startButton.keyEquivalent = "\r"
        startButton.setAccessibilityHelp("自动识别歌单来源并开始迁移或下载")
        startButton.widthAnchor.constraint(equalToConstant: InterfaceStyle.primaryButtonWidth).isActive = true
        startButton.heightAnchor.constraint(equalToConstant: InterfaceStyle.controlHeight).isActive = true

        let sourceRow = NSStackView(views: [sourceURLField, startButton])
        sourceRow.orientation = .horizontal
        sourceRow.alignment = .centerY
        sourceRow.spacing = 10
        sourceURLField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sourceURLField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        startButton.setContentHuggingPriority(.required, for: .horizontal)

        let taskTitle = NSTextField(labelWithString: "自动处理")
        taskTitle.font = InterfaceStyle.sectionTitle
        taskTitle.alignment = .left
        taskTitle.maximumNumberOfLines = 1

        let taskDetail = NSTextField(wrappingLabelWithString: "识别歌曲后直接下载")
        taskDetail.font = InterfaceStyle.body
        taskDetail.textColor = .secondaryLabelColor
        taskDetail.lineBreakMode = .byWordWrapping

        let taskCopy = NSStackView(views: [taskTitle, taskDetail])
        taskCopy.orientation = .vertical
        taskCopy.alignment = .leading
        taskCopy.spacing = 3
        taskCopy.translatesAutoresizingMaskIntoConstraints = false
        taskCopy.setContentHuggingPriority(.defaultLow, for: .horizontal)
        taskCopy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let taskHeader = taskCopy

        mainStatusTitleLabel.font = InterfaceStyle.bodyEmphasis
        mainStatusLabel.font = InterfaceStyle.secondary
        mainStatusLabel.textColor = .secondaryLabelColor
        mainStatusLabel.maximumNumberOfLines = 3
        mainStatusLabel.lineBreakMode = .byWordWrapping

        downloadProgressBar.style = .bar
        downloadProgressBar.isIndeterminate = true
        downloadProgressBar.isDisplayedWhenStopped = false
        downloadProgressBar.controlSize = .small
        downloadProgressBar.translatesAutoresizingMaskIntoConstraints = false
        downloadProgressBar.isHidden = true

        downloadInfoLabel.font = InterfaceStyle.caption
        downloadInfoLabel.textColor = .tertiaryLabelColor
        downloadInfoLabel.maximumNumberOfLines = 1
        downloadInfoLabel.lineBreakMode = .byTruncatingTail
        downloadInfoLabel.isHidden = true

        mainStatusIcon.imageScaling = .scaleProportionallyUpOrDown
        mainStatusSpinner.style = .spinning
        mainStatusSpinner.controlSize = .small
        mainStatusSpinner.isDisplayedWhenStopped = false

        let statusIndicator = NSView()
        mainStatusIcon.translatesAutoresizingMaskIntoConstraints = false
        mainStatusSpinner.translatesAutoresizingMaskIntoConstraints = false
        statusIndicator.addSubview(mainStatusIcon)
        statusIndicator.addSubview(mainStatusSpinner)

        let statusText = NSStackView(views: [mainStatusTitleLabel, mainStatusLabel, downloadProgressBar, downloadInfoLabel])
        statusText.orientation = .vertical
        statusText.alignment = .leading
        statusText.spacing = 2
        statusText.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let statusRow = NSStackView(views: [statusIndicator, statusText])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 11

        let statusBox = makeCard(
            contentView: statusRow,
            style: .status,
            radius: 9,
            horizontalMargin: 13,
            verticalMargin: 11
        )

        let primaryContent = NSStackView(views: [taskHeader, sourceRow, statusBox])
        primaryContent.orientation = .vertical
        primaryContent.alignment = .width
        primaryContent.spacing = 18
        primaryContent.translatesAutoresizingMaskIntoConstraints = false

        let primaryCard = makeCard(
            contentView: primaryContent,
            style: .card,
            radius: 13,
            horizontalMargin: 20,
            verticalMargin: 20,
            interactive: true
        )

        advancedDisclosureButton.target = self
        advancedDisclosureButton.action = #selector(toggleAdvanced(_:))
        advancedDisclosureButton.bezelStyle = .inline
        advancedDisclosureButton.isBordered = false
        advancedDisclosureButton.imagePosition = .imageLeading
        advancedDisclosureButton.alignment = .left
        advancedDisclosureButton.font = InterfaceStyle.bodyEmphasis
        advancedDisclosureButton.contentTintColor = .secondaryLabelColor
        advancedDisclosureButton.setAccessibilityHelp("展开公开 Apple Music 歌单下载功能")

        advancedSummaryLabel.font = InterfaceStyle.secondary
        advancedSummaryLabel.textColor = .tertiaryLabelColor
        advancedSummaryLabel.alignment = .right

        let flexibleSpace = NSView()
        flexibleSpace.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let advancedHeader = NSStackView(views: [advancedDisclosureButton, flexibleSpace, advancedSummaryLabel])
        advancedHeader.orientation = .horizontal
        advancedHeader.alignment = .centerY
        advancedHeader.spacing = 8
        advancedHeader.isHidden = true
        advancedHeaderView = advancedHeader

        let advancedBox = makeAdvancedDownloadBox()
        self.advancedBox = advancedBox

        let stack = NSStackView(views: [header, devicePanel, primaryCard, advancedHeader, advancedBox])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 18
        stack.setCustomSpacing(20, after: header)
        stack.setCustomSpacing(14, after: advancedHeader)
        stack.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stack)

        let sidebarWidthConstraint = sidebar.widthAnchor.constraint(equalToConstant: 190)
        self.sidebarWidthConstraint = sidebarWidthConstraint

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            background.topAnchor.constraint(equalTo: contentView.topAnchor),
            background.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            sidebar.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: background.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            sidebarWidthConstraint,
            sidebarIcon.widthAnchor.constraint(equalToConstant: 20),
            sidebarIcon.heightAnchor.constraint(equalToConstant: 20),
            sidebarStack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            sidebarStack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -16),
            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 58),
            sidebarStack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -18),
            toolbar.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            // Leave a titlebar-safe breathing band under the traffic lights.
            toolbar.topAnchor.constraint(equalTo: background.topAnchor, constant: 34),
            toolbar.heightAnchor.constraint(equalToConstant: 54),
            scrollView.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 28),
            stack.widthAnchor.constraint(equalTo: documentView.widthAnchor, constant: -56),
            stack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 30),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -28),

            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            devicePanel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            primaryCard.widthAnchor.constraint(equalTo: stack.widthAnchor),
            advancedHeader.widthAnchor.constraint(equalTo: stack.widthAnchor),
            advancedBox.widthAnchor.constraint(equalTo: stack.widthAnchor),

            primaryContent.widthAnchor.constraint(greaterThanOrEqualToConstant: 560),
            taskHeader.widthAnchor.constraint(equalTo: primaryContent.widthAnchor),
            sourceRow.widthAnchor.constraint(equalTo: primaryContent.widthAnchor),
            sourceRow.widthAnchor.constraint(greaterThanOrEqualToConstant: 330),
            taskDetail.widthAnchor.constraint(equalTo: taskCopy.widthAnchor),
            statusBox.widthAnchor.constraint(equalTo: primaryContent.widthAnchor),
            downloadProgressBar.widthAnchor.constraint(equalTo: primaryContent.widthAnchor, constant: -57),
            downloadProgressBar.heightAnchor.constraint(equalToConstant: 4),
            statusIndicator.widthAnchor.constraint(equalToConstant: 20),
            statusIndicator.heightAnchor.constraint(equalToConstant: 20),
            mainStatusIcon.centerXAnchor.constraint(equalTo: statusIndicator.centerXAnchor),
            mainStatusIcon.centerYAnchor.constraint(equalTo: statusIndicator.centerYAnchor),
            mainStatusIcon.widthAnchor.constraint(equalToConstant: 18),
            mainStatusIcon.heightAnchor.constraint(equalToConstant: 18),
            mainStatusSpinner.centerXAnchor.constraint(equalTo: statusIndicator.centerXAnchor),
            mainStatusSpinner.centerYAnchor.constraint(equalTo: statusIndicator.centerYAnchor)
        ])

        setAdvancedExpanded(false)
        setSettingsExpanded(false)
        setLogExpanded(false)
        setMainStatus(
            title: "等待链接",
            detail: "粘贴后点击开始",
            kind: .idle
        )
        refreshIPodPanel()
        updateResponsiveLayout()
    }

    func windowDidResize(_ notification: Notification) {
        updateResponsiveLayout()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        updateResponsiveLayout()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        updateResponsiveLayout()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        updateResponsiveLayout()
    }

    func updateResponsiveLayout() {
        guard let contentView = window?.contentView else { return }
        // Keep the beginner flow focused on one task. Advanced workspace
        // navigation stays available through the failure recovery panel.
        let compact = true
        guard compact != isCompactLayout else { return }
        isCompactLayout = compact
        sidebarWidthConstraint?.constant = compact ? 0 : 190
        sidebarView?.isHidden = compact
        sidebarStackView?.isHidden = compact
        contentView.layoutSubtreeIfNeeded()
    }

    private func revealInMainScroll(_ view: NSView) {
        guard let scrollView = mainScrollView,
              let documentView = scrollView.documentView else { return }
        let rect = view.convert(view.bounds, to: documentView).insetBy(dx: 0, dy: -20)
        let viewportHeight = scrollView.contentView.bounds.height
        let documentHeight = documentView.bounds.height
        let maxY = max(0, documentHeight - viewportHeight)
        let targetY = min(max(0, rect.minY), maxY)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func makeIPodDevicePanel() -> NSView {
        let iconContainer = NSView()
        iconContainer.wantsLayer = true
        iconContainer.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
        iconContainer.layer?.cornerRadius = 15
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView(image: NSImage(
            systemSymbolName: "externaldrive.fill",
            accessibilityDescription: "iPod"
        ) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setAccessibilityLabel("iPod 设备")
        iconContainer.addSubview(icon)
        deviceIconContainer = iconContainer
        deviceIcon = icon

        let title = NSTextField(labelWithString: "iPod 未连接")
        title.font = InterfaceStyle.prominentBody
        title.lineBreakMode = .byTruncatingTail
        deviceTitleLabel = title

        let detail = NSTextField(labelWithString: "连接可写的 Rockbox iPod 后可导入")
        detail.font = InterfaceStyle.secondary
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        deviceDetailLabel = detail

        let status = NSTextField(labelWithString: "等待连接")
        status.font = InterfaceStyle.captionEmphasis
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        deviceStatusLabel = status

        let copy = NSStackView(views: [title, detail, status])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 3
        copy.translatesAutoresizingMaskIntoConstraints = false

        let importButton = NSButton(title: "等待连接", target: self, action: #selector(startManualIPodImport(_:)))
        importButton.bezelStyle = .rounded
        importButton.controlSize = .large
        importButton.font = InterfaceStyle.button
        importButton.bezelColor = .controlAccentColor
        importButton.contentTintColor = .white
        importButton.image = NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: "开始导入")
        importButton.imagePosition = .imageLeading
        importButton.setAccessibilityLabel("开始导入")
        importButton.setAccessibilityHelp("连接可写的 Rockbox iPod 后才能开始导入")
        importButton.isEnabled = false
        importButton.setContentHuggingPriority(.required, for: .horizontal)
        importButton.widthAnchor.constraint(equalToConstant: InterfaceStyle.importButtonWidth).isActive = true
        importButton.heightAnchor.constraint(equalToConstant: InterfaceStyle.controlHeight).isActive = true
        deviceImportButton = importButton

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [iconContainer, copy, spacer, importButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let panel = makeCard(
            contentView: row,
            style: .status,
            radius: 13,
            horizontalMargin: 16,
            verticalMargin: 14,
            interactive: true
        )
        panel.setAccessibilityElement(true)
        panel.setAccessibilityLabel("iPod 连接状态")
        panel.setAccessibilityHelp("连接可写的 Rockbox iPod 后才能开始导入")
        panel.isHidden = false

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 52),
            iconContainer.heightAnchor.constraint(equalToConstant: 52),
            icon.widthAnchor.constraint(equalToConstant: 27),
            icon.heightAnchor.constraint(equalToConstant: 27),
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            copy.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
        return panel
    }

    private func makeAdvancedDownloadBox() -> NSView {
        let title = NSTextField(labelWithString: "下载设置")
        title.font = InterfaceStyle.prominentBody

        let detail = NSTextField(wrappingLabelWithString: "出错时检查连接设置或日志。")
        detail.font = InterfaceStyle.body
        detail.textColor = .secondaryLabelColor

        downloadStatusLabel.font = InterfaceStyle.secondary
        downloadStatusLabel.textColor = .secondaryLabelColor
        downloadStatusLabel.maximumNumberOfLines = 3
        downloadStatusLabel.lineBreakMode = .byWordWrapping

        binaryPathField.placeholderString = "/path/to/amdl"
        workingDirectoryField.placeholderString = "/path/to/amdl 工作目录（含 config.yaml）"
        wrapperLauncherField.placeholderString = "可选：wrapper 启动脚本"
        wrapperURLField.stringValue = "http://127.0.0.1:12340"
        if !amdlPath.isEmpty { binaryPathField.stringValue = amdlPath }
        if !workingDirectory.isEmpty { workingDirectoryField.stringValue = workingDirectory }
        if let wrapperLauncherPath, !wrapperLauncherPath.isEmpty {
            wrapperLauncherField.stringValue = wrapperLauncherPath
        }

        settingsDisclosureButton.target = self
        settingsDisclosureButton.action = #selector(toggleSettings(_:))
        configureDisclosureButton(settingsDisclosureButton, help: "展开本地下载器与 wrapper 连接设置")

        let settingsHint = NSTextField(wrappingLabelWithString: "通常不需要修改。")
        settingsHint.font = InterfaceStyle.secondary
        settingsHint.textColor = .secondaryLabelColor

        let labeledFields = [
            makeLabeledField(title: "amdl 可执行文件", field: binaryPathField),
            makeLabeledField(title: "工作目录", field: workingDirectoryField),
            makeLabeledField(title: "wrapper 启动脚本", field: wrapperLauncherField),
            makeLabeledField(title: "wrapper 地址", field: wrapperURLField)
        ]
        let settingsStack = NSStackView(views: [settingsHint] + labeledFields)
        settingsStack.orientation = .vertical
        settingsStack.alignment = .width
        settingsStack.spacing = 10
        settingsStack.translatesAutoresizingMaskIntoConstraints = false
        settingsContainer.addSubview(settingsStack)
        labeledFields.forEach { $0.widthAnchor.constraint(equalTo: settingsStack.widthAnchor).isActive = true }

        configureTextField(binaryPathField, fontSize: 13)
        configureTextField(workingDirectoryField, fontSize: 13)
        configureTextField(wrapperLauncherField, fontSize: 13)
        configureTextField(wrapperURLField, fontSize: 13)

        logDisclosureButton.target = self
        logDisclosureButton.action = #selector(toggleLog(_:))
        configureDisclosureButton(logDisclosureButton, help: "展开下载器运行日志")

        logView.isEditable = false
        logView.isSelectable = true
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textContainerInset = NSSize(width: 10, height: 10)
        logView.backgroundColor = .textBackgroundColor
        let logScroll = NSScrollView()
        logScroll.hasVerticalScroller = true
        logScroll.autohidesScrollers = true
        logScroll.borderType = .bezelBorder
        logScroll.documentView = logView
        logScrollView = logScroll

        let content = NSStackView(views: [
            title,
            detail,
            downloadStatusLabel,
            settingsDisclosureButton,
            settingsContainer,
            logDisclosureButton,
            logScroll
        ])
        content.orientation = .vertical
        content.alignment = .width
        content.spacing = 10
        content.setCustomSpacing(5, after: title)
        content.setCustomSpacing(14, after: detail)
        content.setCustomSpacing(14, after: downloadStatusLabel)
        content.setCustomSpacing(4, after: settingsDisclosureButton)
        content.setCustomSpacing(12, after: settingsContainer)

        NSLayoutConstraint.activate([
            detail.widthAnchor.constraint(equalTo: content.widthAnchor),
            downloadStatusLabel.widthAnchor.constraint(equalTo: content.widthAnchor),
            settingsContainer.widthAnchor.constraint(equalTo: content.widthAnchor),
            settingsStack.leadingAnchor.constraint(equalTo: settingsContainer.leadingAnchor),
            settingsStack.trailingAnchor.constraint(equalTo: settingsContainer.trailingAnchor),
            settingsStack.topAnchor.constraint(equalTo: settingsContainer.topAnchor),
            settingsStack.bottomAnchor.constraint(equalTo: settingsContainer.bottomAnchor),
            settingsHint.widthAnchor.constraint(equalTo: settingsStack.widthAnchor),
            logScroll.widthAnchor.constraint(equalTo: content.widthAnchor),
            logScroll.heightAnchor.constraint(equalToConstant: 140),
            logView.widthAnchor.constraint(equalTo: logScroll.widthAnchor),
            logView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140)
        ])
        return makeCard(
            contentView: content,
            style: .card,
            radius: 13,
            horizontalMargin: 20,
            verticalMargin: 20,
            interactive: true
        )
    }

    private func makeCard(
        contentView: NSView,
        style: CardContainerView.Style,
        radius: CGFloat,
        horizontalMargin: CGFloat,
        verticalMargin: CGFloat,
        interactive: Bool = false
    ) -> NSView {
        if #available(macOS 26.0, *) {
            return GlassSurfaceView(
                contentView: contentView,
                cornerRadius: radius,
                interactive: interactive,
                insets: NSEdgeInsets(
                    top: verticalMargin,
                    left: horizontalMargin,
                    bottom: verticalMargin,
                    right: horizontalMargin
                )
            )
        }
        return CardContainerView(
            contentView: contentView,
            style: style,
            radius: radius,
            horizontalMargin: horizontalMargin,
            verticalMargin: verticalMargin
        )
    }

    private func makeLabeledField(title: String, field: NSTextField) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = InterfaceStyle.secondaryEmphasis
        field.setAccessibilityLabel(title)
        let stack = NSStackView(views: [label, field])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    /// Keep text entry consistent with native macOS controls across the main
    /// flow and the optional connection settings.
    private func configureTextField(_ field: NSTextField, fontSize: CGFloat) {
        field.font = .systemFont(ofSize: fontSize)
        field.controlSize = .large
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.isBordered = true
        field.drawsBackground = true
        field.backgroundColor = .textBackgroundColor
        field.focusRingType = .default
        field.alignment = .left
        field.heightAnchor.constraint(equalToConstant: InterfaceStyle.controlHeight).isActive = true
    }

    private func makeSidebarButton(
        title: String,
        symbolName: String,
        selected: Bool,
        action: Selector?
    ) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.contentTintColor = selected ? .labelColor : .secondaryLabelColor
        button.font = selected ? InterfaceStyle.bodyEmphasis : InterfaceStyle.body
        button.controlSize = .large
        button.widthAnchor.constraint(equalToConstant: 158).isActive = true
        button.heightAnchor.constraint(equalToConstant: InterfaceStyle.controlHeight).isActive = true
        button.setAccessibilityLabel(title)

        if selected {
            button.bezelStyle = .rounded
            button.isBordered = true
            button.bezelColor = NSColor.labelColor.withAlphaComponent(0.10)
        } else {
            button.bezelStyle = .inline
            button.isBordered = false
        }

        if action != nil {
            button.target = self
            button.action = action
        }
        return button
    }

    private func setSidebarSelection(_ selectedButton: NSButton) {
        let buttons = [sidebarImportButton, sidebarDownloadButton, sidebarSettingsButton].compactMap { $0 }
        for button in buttons {
            let isSelected = button === selectedButton
            button.contentTintColor = isSelected ? .labelColor : .secondaryLabelColor
            button.font = isSelected ? InterfaceStyle.bodyEmphasis : InterfaceStyle.body
            button.isBordered = isSelected
            button.bezelStyle = isSelected ? .rounded : .inline
            button.bezelColor = isSelected ? NSColor.labelColor.withAlphaComponent(0.10) : nil
        }
    }

    private func configureDisclosureButton(_ button: NSButton, help: String) {
        button.bezelStyle = .inline
        button.isBordered = false
        button.imagePosition = .imageLeading
        button.alignment = .left
        button.font = InterfaceStyle.secondaryEmphasis
        button.contentTintColor = .secondaryLabelColor
        button.setAccessibilityHelp(help)
    }

    @objc private func selectDownloadFromSidebar(_ sender: Any?) {
        if let sidebarDownloadButton { setSidebarSelection(sidebarDownloadButton) }
        workspaceTitleLabel.stringValue = "Apple Music 下载"
        workspaceToolbarHint.stringValue = "公开歌单"
        setAdvancedExpanded(true)
        window?.contentView?.layoutSubtreeIfNeeded()
        revealInMainScroll(sourceURLField)
        window?.makeFirstResponder(sourceURLField)
    }

    @objc private func selectImportFromSidebar(_ sender: Any?) {
        if let sidebarImportButton { setSidebarSelection(sidebarImportButton) }
        workspaceTitleLabel.stringValue = "Music Bridge"
        workspaceToolbarHint.stringValue = "就绪"
        setAdvancedExpanded(false)
        setSettingsExpanded(false)
        setLogExpanded(false)
        if let scrollView = mainScrollView {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        window?.makeFirstResponder(sourceURLField)
    }

    func showConnectionSettings() {
        showWindow(nil)
        selectSettingsFromSidebar(nil)
    }

    func showRunLog() {
        showWindow(nil)
        setAdvancedExpanded(true)
        setLogExpanded(true)
        window?.contentView?.layoutSubtreeIfNeeded()
        if let logScrollView { revealInMainScroll(logScrollView) }
    }

    @objc private func selectSettingsFromSidebar(_ sender: Any?) {
        if let sidebarSettingsButton { setSidebarSelection(sidebarSettingsButton) }
        workspaceTitleLabel.stringValue = "连接设置"
        workspaceToolbarHint.stringValue = "本地服务"
        setAdvancedExpanded(true)
        setSettingsExpanded(true)
        window?.contentView?.layoutSubtreeIfNeeded()
        revealInMainScroll(binaryPathField)
        window?.makeFirstResponder(binaryPathField)
    }

    @objc private func pasteFromClipboard(_ sender: Any?) {
        guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else {
            workspaceToolbarHint.stringValue = "剪贴板没有文本"
            window?.makeFirstResponder(sourceURLField)
            return
        }
        sourceURLField.stringValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        workspaceTitleLabel.stringValue = "导入歌单"
        workspaceToolbarHint.stringValue = "链接已粘贴"
        if let sidebarImportButton { setSidebarSelection(sidebarImportButton) }
        window?.makeFirstResponder(sourceURLField)
    }

    private enum MainStatusKind {
        case idle
        case loading
        case success
        case failure
    }

    private func setMainStatus(title: String, detail: String, kind: MainStatusKind) {
        mainStatusTitleLabel.stringValue = title
        mainStatusLabel.stringValue = detail

        let symbolName: String
        let tintColor: NSColor
        switch kind {
        case .idle:
            symbolName = "link"
            tintColor = .secondaryLabelColor
            mainStatusSpinner.stopAnimation(nil)
        case .loading:
            symbolName = "hourglass"
            tintColor = .controlAccentColor
            mainStatusSpinner.startAnimation(nil)
        case .success:
            symbolName = "checkmark.circle.fill"
            tintColor = .systemGreen
            mainStatusSpinner.stopAnimation(nil)
        case .failure:
            symbolName = "exclamationmark.triangle.fill"
            tintColor = .systemRed
            mainStatusSpinner.stopAnimation(nil)
        }

        mainStatusIcon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        mainStatusIcon.contentTintColor = tintColor
        mainStatusIcon.isHidden = kind == .loading
        mainStatusSpinner.isHidden = kind != .loading
        mainStatusTitleLabel.setAccessibilityLabel(title)
        mainStatusLabel.setAccessibilityLabel(detail)
    }

    /// The beginner flow has one physical action control. It switches between
    /// starting a new task and stopping the active download instead of adding
    /// a second button in the advanced panel.
    private func setPrimaryButtonToStart(title: String) {
        startButton.target = self
        startButton.action = #selector(startOneClick(_:))
        startButton.title = title
        startButton.keyEquivalent = "\r"
        startButton.isEnabled = true
        startButton.setAccessibilityLabel(title == "重试" ? "重试" : "开始")
        startButton.setAccessibilityHelp("自动识别歌单来源并开始迁移或下载")
    }

    private func setPrimaryButtonToStop() {
        startButton.target = self
        startButton.action = #selector(stopDownload(_:))
        startButton.title = "停止"
        startButton.keyEquivalent = ""
        startButton.isEnabled = true
        startButton.setAccessibilityLabel("停止")
        startButton.setAccessibilityHelp("停止当前下载任务")
    }

    private func beginDownloadProgress() {
        downloadStartedAt = Date()
        downloadProgressBar.isHidden = false
        downloadProgressBar.isIndeterminate = true
        downloadProgressBar.doubleValue = 0
        downloadProgressBar.startAnimation(nil)
        downloadInfoLabel.isHidden = false
        downloadInfoLabel.stringValue = "正在连接 Apple Music"
        progressTimer?.invalidate()
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(updateElapsedDownloadTime(_:)), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    @objc private func updateElapsedDownloadTime(_ timer: Timer) {
        guard let startedAt = downloadStartedAt else { return }
        if isMatchingCatalog || isIPodImporting { return }
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        downloadInfoLabel.stringValue = String(format: "已用时 %02d:%02d", minutes, seconds)
    }

    private func endDownloadProgress() {
        isMatchingCatalog = false
        progressTimer?.invalidate()
        progressTimer = nil
        downloadStartedAt = nil
        downloadProgressBar.stopAnimation(nil)
        downloadProgressBar.isHidden = true
        downloadInfoLabel.isHidden = true
        downloadInfoLabel.stringValue = ""
    }

    private func isProgressOutput(_ line: String) -> Bool {
        line.range(of: "\\d{1,3}%", options: .regularExpression) != nil ||
            line.localizedCaseInsensitiveContains("downloading") ||
            line.localizedCaseInsensitiveContains("decrypting") ||
            line.range(of: "Queue \\d+ of \\d+", options: .regularExpression) != nil
    }

    private func updateDownloadProgress(from line: String) {
        guard downloadStartedAt != nil else { return }
        if let match = line.range(of: "\\d{1,3}%", options: .regularExpression),
           let percent = Double(String(line[match].dropLast())) {
            downloadProgressBar.isIndeterminate = false
            downloadProgressBar.doubleValue = min(100, max(0, percent))
            downloadProgressBar.startAnimation(nil)
            downloadInfoLabel.isHidden = false
            downloadInfoLabel.stringValue = String(format: "正在下载 · %.0f%%", percent)
            return
        }

        if line.localizedCaseInsensitiveContains("decrypting") {
            downloadInfoLabel.isHidden = false
            downloadInfoLabel.stringValue = "正在封装音频"
        } else if line.localizedCaseInsensitiveContains("downloading") {
            downloadInfoLabel.isHidden = false
            downloadInfoLabel.stringValue = "正在下载"
        } else if let match = line.range(of: "Queue \\d+ of \\d+", options: .regularExpression) {
            let queue = String(line[match])
            let parts = queue.split(separator: " ")
            if parts.count == 4,
               let current = Double(parts[1]),
               let total = Double(parts[3]), total > 0 {
                downloadProgressBar.isIndeterminate = false
                downloadProgressBar.doubleValue = current / total * 100
                downloadProgressBar.startAnimation(nil)
                downloadInfoLabel.isHidden = false
                downloadInfoLabel.stringValue = "正在处理 · \(Int(current)) / \(Int(total))"
            }
        }
    }

    @objc private func toggleAdvanced(_ sender: Any?) {
        setAdvancedExpanded(!isAdvancedExpanded)
    }

    private func setVisibility(_ view: NSView?, expanded: Bool) {
        guard let view else { return }
        let shouldAnimate = window?.isVisible == true && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if expanded {
            view.isHidden = false
            view.alphaValue = shouldAnimate ? 0 : 1
            if shouldAnimate {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    view.animator().alphaValue = 1
                }
            }
        } else if shouldAnimate && !view.isHidden {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                view.animator().alphaValue = 0
            }, completionHandler: { [weak view] in
                guard let view, view.alphaValue < 0.5 else { return }
                view.isHidden = true
                view.alphaValue = 1
            })
        } else {
            view.isHidden = true
            view.alphaValue = 1
        }
    }

    private func setAdvancedExpanded(_ expanded: Bool) {
        isAdvancedExpanded = expanded
        advancedHeaderView?.isHidden = !expanded
        setVisibility(advancedBox, expanded: expanded)
        advancedDisclosureButton.image = NSImage(
            systemSymbolName: expanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
        advancedDisclosureButton.setAccessibilityValue(expanded ? "已展开" : "已收起")
        advancedSummaryLabel.stringValue = expanded ? "错误详情与设置" : "出错时展开"
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    @objc private func toggleSettings(_ sender: Any?) {
        setSettingsExpanded(!isSettingsExpanded)
    }

    private func setSettingsExpanded(_ expanded: Bool) {
        isSettingsExpanded = expanded
        setVisibility(settingsContainer, expanded: expanded)
        settingsDisclosureButton.image = NSImage(
            systemSymbolName: expanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
        settingsDisclosureButton.setAccessibilityValue(expanded ? "已展开" : "已收起")
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    @objc private func toggleLog(_ sender: Any?) {
        setLogExpanded(!isLogExpanded)
    }

    private func setLogExpanded(_ expanded: Bool) {
        isLogExpanded = expanded
        setVisibility(logScrollView, expanded: expanded)
        logDisclosureButton.image = NSImage(
            systemSymbolName: expanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
        logDisclosureButton.setAccessibilityValue(expanded ? "已展开" : "已收起")
        window?.contentView?.layoutSubtreeIfNeeded()
    }

    @objc private func startOneClick(_ sender: Any?) {
        let source = sourceURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else {
            setMainStatus(
                title: "还缺一个链接",
                detail: "请先粘贴网易云歌单或公开的 Apple Music 歌单链接。",
                kind: .failure
            )
            window?.makeFirstResponder(sourceURLField)
            return
        }
        guard let sourceURL = URL(string: source), let scheme = sourceURL.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            setMainStatus(
                title: "链接格式不正确",
                detail: "链接需要以 http:// 或 https:// 开头，请检查后重试。",
                kind: .failure
            )
            window?.makeFirstResponder(sourceURLField)
            return
        }

        if isPublicApplePlaylistURL(source) {
            if let sidebarDownloadButton { setSidebarSelection(sidebarDownloadButton) }
            workspaceTitleLabel.stringValue = "Apple Music 下载"
            workspaceToolbarHint.stringValue = "公开歌单"
            setMainStatus(
                title: "已识别 Apple Music 歌单",
                detail: "正在检查本地下载服务并准备下载。",
                kind: .loading
            )
            startDownload(sourceURL: source)
            return
        }

        if let sidebarImportButton { setSidebarSelection(sidebarImportButton) }
        workspaceTitleLabel.stringValue = "Music Bridge"
        workspaceToolbarHint.stringValue = "正在读取"
        startButton.isEnabled = false
        startButton.title = "正在导出…"
        setMainStatus(
            title: "正在读取歌单",
            detail: "正在整理歌名和歌手，通常只需要几秒钟。",
            kind: .loading
        )

        workflowTask?.cancel()
        workflowTask = Task { [weak self] in
            guard let self else { return }
            do {
                let export = try await self.goMusicClient.exportPlaylist(url: source)
                await self.resolveAndStartDirectDownload(export: export)
            } catch {
                if Task.isCancelled { return }
                self.setPrimaryButtonToStart(title: "重试")
                self.setMainStatus(
                    title: "没有成功导出",
                    detail: "\(error.localizedDescription) 请检查链接或网络后重试。",
                    kind: .failure
                )
                self.workspaceToolbarHint.stringValue = "需要重试"
            }
        }
    }

    private func resolveAndStartDirectDownload(export: PlaylistExport) async {
        setMainStatus(
            title: "正在匹配 Apple Music",
            detail: "已读出 \(export.count) 首，正在寻找对应单曲。",
            kind: .loading
        )
        workspaceToolbarHint.stringValue = "正在匹配"
        isMatchingCatalog = true
        beginDownloadProgress()
        downloadInfoLabel.stringValue = "正在搜索 Apple Music"
        setPrimaryButtonToStop()

        do {
            let result = try await catalogClient.match(export: export) { [weak self] current, total in
                guard let self else { return }
                self.downloadProgressBar.isHidden = false
                self.downloadProgressBar.isIndeterminate = false
                self.downloadProgressBar.doubleValue = Double(current) / Double(max(1, total)) * 100
                self.downloadInfoLabel.isHidden = false
                self.downloadInfoLabel.stringValue = "正在匹配 · \(current) / \(total)"
                self.mainStatusLabel.stringValue = "已找到 \(current) / \(total) 首的候选结果。"
            }

            endDownloadProgress()
            if result.skipped.isEmpty {
                setMainStatus(
                    title: "已匹配 \(result.matched) 首",
                    detail: "正在直接启动下载。",
                    kind: .success
                )
            } else {
                let examples = result.skipped.prefix(3).map(\.displayName).joined(separator: "、")
                setMainStatus(
                    title: "匹配 \(result.matched) 首，跳过 \(result.skipped.count) 首",
                    detail: "未确认的版本不会自动下载：\(examples)",
                    kind: .failure
                )
                appendLog("跳过未确认歌曲：\(result.skipped.map(\.displayName).joined(separator: "；"))")
            }
            startDownload(urls: result.urls)
        } catch {
            if Task.isCancelled { return }
            endDownloadProgress()
            setPrimaryButtonToStart(title: "重试")
            setAdvancedExpanded(true)
            setLogExpanded(true)
            downloadStatusLabel.stringValue = error.localizedDescription
            setMainStatus(
                title: "没有找到可下载歌曲",
                detail: "Apple Music 匹配未完成，请检查网络或改用公开 Apple Music 歌单链接。",
                kind: .failure
            )
        }
    }

    private func startDownload(sourceURL: String) {
        workspaceTitleLabel.stringValue = "Apple Music 下载"
        workspaceToolbarHint.stringValue = "公开歌单"
        let appleURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if appleURL.contains("/library/playlist/") {
            setPrimaryButtonToStart(title: "重试")
            downloadStatusLabel.stringValue = "这是资料库链接，请复制公开分享链接。"
            setAdvancedExpanded(true)
            setMainStatus(
                title: "需要公开分享链接",
                detail: "请粘贴公开分享链接",
                kind: .failure
            )
            window?.makeFirstResponder(sourceURLField)
            return
        }
        guard isPublicApplePlaylistURL(appleURL) else {
            setPrimaryButtonToStart(title: "重试")
            downloadStatusLabel.stringValue = "请粘贴公开的 Apple Music 歌单链接。"
            setAdvancedExpanded(true)
            setMainStatus(
                title: "Apple Music 链接无效",
                detail: "请粘贴公开歌单链接",
                kind: .failure
            )
            window?.makeFirstResponder(sourceURLField)
            return
        }

        startDownload(urls: [appleURL])
    }

    private func startDownload(urls: [String]) {
        guard !urls.isEmpty else {
            setPrimaryButtonToStart(title: "重试")
            setMainStatus(title: "没有可下载歌曲", detail: "没有找到可用的 Apple Music 链接。", kind: .failure)
            return
        }
        workspaceTitleLabel.stringValue = "Apple Music 下载"
        workspaceToolbarHint.stringValue = "正在下载"

        let binaryPath = binaryPathField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let workingDirectory = workingDirectoryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrapperURLString = wrapperURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let launcherPath = wrapperLauncherField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !binaryPath.isEmpty, !workingDirectory.isEmpty else {
            setPrimaryButtonToStart(title: "重试")
            downloadStatusLabel.stringValue = "缺少下载器路径，请检查连接设置。"
            setAdvancedExpanded(true)
            setSettingsExpanded(true)
            setMainStatus(
                title: "没有找到本地下载器",
                detail: "请检查连接设置",
                kind: .failure
            )
            return
        }
        guard let wrapperURL = URL(string: wrapperURLString), wrapperURL.scheme != nil, wrapperURL.host != nil else {
            setPrimaryButtonToStart(title: "重试")
            downloadStatusLabel.stringValue = "wrapper 地址无效。"
            setAdvancedExpanded(true)
            setSettingsExpanded(true)
            setMainStatus(
                title: "下载服务地址无效",
                detail: "请检查 wrapper 地址",
                kind: .failure
            )
            return
        }

        amdlPath = binaryPath
        self.workingDirectory = workingDirectory
        wrapperLauncherPath = launcherPath.isEmpty ? nil : launcherPath
        UserDefaults.standard.set(binaryPath, forKey: "amdlPath")
        UserDefaults.standard.set(workingDirectory, forKey: "workingDirectory")
        UserDefaults.standard.set(wrapperLauncherPath, forKey: "wrapperLauncherPath")
        downloadSnapshot = ipodImporter.snapshotAudioFiles(
            in: URL(fileURLWithPath: workingDirectory, isDirectory: true)
        )

        appendLog("准备下载 \(urls.count) 个 Apple Music 链接")
        downloadStatusLabel.stringValue = "正在检查本地下载服务…"
        setAdvancedExpanded(false)
        setMainStatus(
            title: "正在准备下载",
            detail: "正在检查本地下载服务和登录状态。",
            kind: .loading
        )
        setPrimaryButtonToStop()

        downloaderRunner.start(
            binaryPath: binaryPath,
            workingDirectory: workingDirectory,
            urls: urls,
            wrapperLauncherPath: launcherPath.isEmpty ? nil : launcherPath,
            wrapperURL: wrapperURL
        ) { [weak self] result in
            guard let self else { return }
            if case .failure(let error) = result {
                self.setPrimaryButtonToStart(title: "重试")
                self.downloadStatusLabel.stringValue = error.localizedDescription
                self.setAdvancedExpanded(true)
                self.setLogExpanded(true)
                self.setMainStatus(
                    title: "下载服务未就绪",
                    detail: "\(error.localizedDescription) 运行日志已展开。",
                    kind: .failure
                )
            }
        }
    }

    private func queuePendingIPodImport(_ files: [(url: URL, root: URL)]) {
        if !files.isEmpty {
            var existing = Set(pendingImportFiles.map { $0.url.standardizedFileURL.path })
            for file in files where existing.insert(file.url.standardizedFileURL.path).inserted {
                pendingImportFiles.append(file)
            }
        }
        refreshIPodPanel()
        guard !files.isEmpty else {
            setMainStatus(
                title: "下载完成",
                detail: "没有发现本次新增音频文件。",
                kind: .success
            )
            downloadStatusLabel.stringValue = "下载完成"
            return
        }

        let detail = ipodImporter.mountedDevices().isEmpty
            ? "下载完成；连接 iPod 后，点击设备卡片中的开始导入。"
            : "下载完成；点击设备卡片中的开始导入来扫描并复制。"
        setMainStatus(title: "下载完成", detail: detail, kind: .success)
        downloadStatusLabel.stringValue = "等待手动导入"
    }

    private func refreshIPodPanel() {
        guard let panel = devicePanel else { return }
        guard let device = ipodImporter.mountedDevices().first else {
            panel.isHidden = false
            deviceIconContainer?.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.28).cgColor
            deviceIcon?.contentTintColor = .tertiaryLabelColor
            deviceTitleLabel?.stringValue = "iPod 未连接"
            deviceDetailLabel?.stringValue = pendingImportFiles.isEmpty
                ? "连接可写的 Rockbox iPod 后可导入"
                : "连接后可导入 \(pendingImportFiles.count) 首已下载音乐"
            deviceStatusLabel?.stringValue = "等待连接"
            deviceStatusLabel?.textColor = .secondaryLabelColor
            deviceImportButton?.title = "等待连接"
            deviceImportButton?.bezelColor = NSColor.separatorColor.withAlphaComponent(0.28)
            deviceImportButton?.isEnabled = false
            deviceImportButton?.setAccessibilityHelp("连接可写的 Rockbox iPod 后才能开始导入")
            panel.setAccessibilityHelp("连接可写的 Rockbox iPod 后才能开始导入")
            return
        }

        panel.isHidden = false
        deviceIconContainer?.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
        deviceIcon?.contentTintColor = .controlAccentColor
        deviceIcon?.image = NSImage(
            systemSymbolName: "externaldrive.fill",
            accessibilityDescription: "iPod"
        )
        deviceTitleLabel?.stringValue = "iPod 已连接"
        var detail = "\(device.name) · Rockbox · 可写"
        if !pendingImportFiles.isEmpty {
            detail += " · 可导入 \(pendingImportFiles.count) 首"
        }
        deviceDetailLabel?.stringValue = detail
        deviceStatusLabel?.stringValue = isIPodImporting ? "正在导入…" : "连接就绪"
        deviceStatusLabel?.textColor = isIPodImporting ? .controlAccentColor : .systemGreen
        deviceImportButton?.title = isIPodImporting ? "导入中…" : "开始导入"
        deviceImportButton?.bezelColor = .controlAccentColor
        deviceImportButton?.isEnabled = !isIPodImporting
        deviceImportButton?.setAccessibilityHelp("扫描下载目录、去重并导入到已连接的 Rockbox iPod")
        panel.setAccessibilityHelp("连接就绪后，点击开始导入来扫描并复制音乐")
    }

    @objc private func startManualIPodImport(_ sender: Any?) {
        guard !isIPodImporting else { return }
        guard let device = ipodImporter.mountedDevices().first else {
            refreshIPodPanel()
            setMainStatus(
                title: "等待 iPod",
                detail: "未检测到可写的 Rockbox iPod。",
                kind: .idle
            )
            downloadStatusLabel.stringValue = "未检测到可写的 Rockbox iPod"
            return
        }

        let files = ipodImporter.audioFiles(
            in: URL(fileURLWithPath: workingDirectory, isDirectory: true)
        )
        guard !files.isEmpty else {
            setMainStatus(
                title: "没有可导入的音乐",
                detail: "下载目录中没有找到音频文件。",
                kind: .failure
            )
            downloadStatusLabel.stringValue = "没有找到可导入音频"
            return
        }

        pendingImportFiles.removeAll()
        isIPodImporting = true
        startButton.isEnabled = false
        refreshIPodPanel()
        setMainStatus(
            title: "正在扫描并导入",
            detail: "已识别 \(device.name)，正在检查重复、播放能力、码率和封面。",
            kind: .loading
        )
        workspaceToolbarHint.stringValue = "正在导入"
        beginDownloadProgress()
        downloadInfoLabel.stringValue = "正在扫描 \(files.count) 首并复制到 iPod"

        let importer = ipodImporter
        let worker = Task.detached(priority: .utility) {
            let report = importer.importFiles(files, to: device)
            return report
        }
        Task { @MainActor [weak self] in
            let report = await worker.value
            guard let self else { return }
            self.finishIPodImport(report)
        }
    }

    private func finishIPodImport(_ report: IPodImportReport) {
        isIPodImporting = false
        endDownloadProgress()
        report.messages.forEach(appendLog)
        refreshIPodPanel()

        let hasIssues = report.skippedUnplayable > 0 ||
            report.missingSourceCovers > 0 ||
            report.missingDestinationCovers > 0 ||
            report.missingBitrates > 0 ||
            !report.messages.isEmpty
        let coverIssueCount = max(report.missingSourceCovers, report.missingDestinationCovers)
        let coverText = coverIssueCount == 0
            ? "内嵌封面通过"
            : "内嵌封面需检查 \(coverIssueCount) 首"
        let bitrateText = report.missingBitrates == 0
            ? "码率通过"
            : "码率缺失 \(report.missingBitrates) 首"
        let skippedText = report.skippedUnplayable == 0 ? "" : " · 跳过无法播放 \(report.skippedUnplayable) 首"
        let detail = "导入 \(report.imported) 首，已存在 \(report.alreadyPresent) 首 · \(bitrateText) · \(coverText)\(skippedText)"

        setPrimaryButtonToStart(title: "开始")
        setMainStatus(
            title: hasIssues ? "导入完成，有项目需检查" : "已导入 iPod",
            detail: detail,
            kind: hasIssues ? .failure : .success
        )
        downloadStatusLabel.stringValue = detail
        workspaceToolbarHint.stringValue = hasIssues ? "需要检查" : "已完成"
    }

    @objc private func stopDownload(_ sender: Any?) {
        workflowTask?.cancel()
        workflowTask = nil
        if isDownloaderRunning {
            downloaderRunner.stop()
        }
        endDownloadProgress()
        setPrimaryButtonToStart(title: "开始")
        downloadStatusLabel.stringValue = "已停止"
        setMainStatus(
            title: "下载已停止",
            detail: "可修改链接后重试",
            kind: .idle
        )
    }

    private func isPublicApplePlaylistURL(_ value: String) -> Bool {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host?.lowercased(),
              host == "music.apple.com" || host.hasSuffix(".music.apple.com") else {
            return false
        }
        return url.path.contains("/playlist/")
    }

    private func appendLog(_ line: String) {
        let existing = logView.string
        logView.string = existing.isEmpty ? line : existing + "\n" + line
        logView.scrollToEndOfDocument(nil)
    }

    private func revealDownloadDirectory() -> String {
        let baseURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        let fileManager = FileManager.default
        let configuredFolders = [
            "alac-save-folder",
            "atmos-save-folder",
            "aac-save-folder",
            "mv-save-folder"
        ].compactMap { key -> URL? in
            let configURL = URL(fileURLWithPath: workingDirectory).appendingPathComponent("config.yaml")
            guard let contents = try? String(contentsOf: configURL, encoding: .utf8),
                  let line = contents.split(whereSeparator: \.isNewline).first(where: {
                      String($0).trimmingCharacters(in: .whitespaces).hasPrefix("\(key):")
                  }) else {
                return nil
            }
            let rawValue = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                .dropFirst()
                .joined(separator: ":")
                .trimmingCharacters(in: .whitespaces)
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: true)
                .first
                .map(String.init) ?? ""
            let folder = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            guard !folder.isEmpty else { return nil }
            return baseURL.appendingPathComponent(folder, isDirectory: true)
        }

        let candidates = configuredFolders.filter {
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: $0.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        let target = candidates.max {
            let lhs = (try? fileManager.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date) ?? .distantPast
            let rhs = (try? fileManager.attributesOfItem(atPath: $1.path)[.modificationDate] as? Date) ?? .distantPast
            return lhs < rhs
        } ?? baseURL

        guard fileManager.fileExists(atPath: target.path) else {
            let message = "下载完成，但找不到保存目录：\(target.path)"
            downloadStatusLabel.stringValue = message
            return message
        }
        if NSWorkspace.shared.open(target) {
            let message = "下载完成，已在 Finder 中打开：\(target.path)"
            downloadStatusLabel.stringValue = message
            return message
        } else {
            let message = "下载完成，但无法自动打开保存目录：\(target.path)"
            downloadStatusLabel.stringValue = message
            return message
        }
    }
}
