import SwiftUI

private enum Paint {
    static let background = Color(red: 78/255, green: 80/255, blue: 83/255)
    static let card = Color(red: 52/255, green: 54/255, blue: 61/255)
    static let input = Color(red: 35/255, green: 38/255, blue: 41/255)
    static let white = Color(red: 246/255, green: 246/255, blue: 247/255)
    static let secondary = Color(red: 173/255, green: 177/255, blue: 185/255)
    static let placeholder = Color(red: 128/255, green: 135/255, blue: 145/255)
    static let blue = Color(red: 40/255, green: 146/255, blue: 255/255)
    static let green = Color(red: 64/255, green: 201/255, blue: 135/255)
    static let line = Color.white.opacity(0.105)
}

struct BridgeView: View {
    @ObservedObject var model: BridgeModel
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    header.frame(height: 83, alignment: .topLeading)
                    Rectangle().fill(Paint.line).frame(height: 1).padding(.top, 28)
                    HStack(alignment: .top, spacing: 23) {
                        VStack(spacing: 20) {
                            sourceCard
                            progressCard
                            disclosures
                        }
                        .frame(maxWidth: .infinity)
                        deviceCard.frame(width: max(310, (geometry.size.width - 89) * (377.0 / 1091.0)))
                    }
                    .padding(.top, 26)
                }
                .padding(.horizontal, 33)
                .padding(.top, 33)
                .padding(.bottom, 33)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollIndicators(.hidden)
            .background(WindowBackdrop())
            .animation(reduceMotion ? nil : .smooth(duration: 0.28, extraBounce: 0), value: model.settingsExpanded)
            .animation(reduceMotion ? nil : .smooth(duration: 0.24, extraBounce: 0), value: model.logsExpanded)
        }
        .foregroundStyle(Paint.white)
        .font(.system(size: 13))
        .preferredColorScheme(.dark)
        .environment(\.legibilityWeight, .regular)
        .ignoresSafeArea()
    }

    private var header: some View {
        ZStack(alignment: .topLeading) {
            Text("让歌单继续留在你的 iPod 里")
                .font(.system(size: 48, weight: .bold))
                .tracking(-2.15)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .frame(height: 62, alignment: .topLeading)
                .offset(x: 2.5)
            HStack(alignment: .center, spacing: 12) {
                Text("粘贴网易云或 Apple Music 公开歌单链接，完成下载后，再由你决定何时导入 Rockbox。")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Paint.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .offset(x: 2)
                Spacer(minLength: 0)
            }
            .frame(height: 35)
            .padding(.top, 56.5)
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("歌单来源").font(.system(size: 15.75, weight: .semibold))
                Spacer()
                BridgeIcon(kind: .link).frame(width: 12, height: 12).foregroundStyle(Paint.secondary)
                Text(sourceStatus).font(.system(size: 12, weight: .regular)).foregroundStyle(Paint.secondary)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: sourceStatus)
            }
            Text("自动识别链接来源，不需要切换平台。")
                .font(.system(size: 12.5, weight: .regular)).foregroundStyle(Paint.secondary).padding(.top, 8)
            HStack(spacing: 10) {
                HStack(spacing: 11) {
                    BridgeIcon(kind: .link).frame(width: 14, height: 14).foregroundStyle(Paint.placeholder)
                    ZStack(alignment: .leading) {
                        if model.source.isEmpty {
                            Text("粘贴公开歌单链接...").foregroundStyle(Paint.placeholder).allowsHitTesting(false)
                        }
                        TextField("", text: $model.source)
                        .textFieldStyle(.plain)
                        .focused($inputFocused)
                        .onSubmit { model.startOrStop() }
                        .onExitCommand { inputFocused = false }
                        .accessibilityLabel("公开歌单链接")
                        .disabled(model.busy || model.importing)
                    }.font(.system(size: 16, weight: .regular))
                    Button { model.source = ""; inputFocused = true } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Paint.placeholder.opacity(model.source.isEmpty ? 0.6 : 1))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.035), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.busy || model.importing)
                    .accessibilityLabel("清除链接")
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Paint.input, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(inputFocused ? Paint.blue : Color.white.opacity(0.14), lineWidth: 1))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: inputFocused)
                Button { model.startOrStop() } label: {
                    HStack(spacing: 10) {
                        BridgeIcon(kind: model.busy ? .stop : .download).frame(width: 16, height: 16)
                        Text(model.busy ? "停止" : "开始")
                    }
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 108, height: 46)
                }
                .buttonStyle(BlueButtonStyle())
                .disabled(model.importing)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.top, 19)
            Text("支持 music.163.com 与 music.apple.com")
                .font(.system(size: 12.5)).foregroundStyle(Paint.secondary).padding(.top, 10)
        }
        .padding(23)
        .frame(maxWidth: .infinity, minHeight: 181, maxHeight: 181, alignment: .topLeading)
        .floatingSurface(editing: inputFocused)
    }

    private var sourceStatus: String {
        if model.source.isEmpty { return "等待链接" }
        switch PlaylistSource.identify(model.source) {
        case .apple: return "Apple Music"
        case .netease: return "网易云音乐"
        case nil: return "请检查链接"
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    Circle().fill(model.failed ? Color.red : model.busy ? Paint.blue : Paint.placeholder).frame(width: 8, height: 8)
                    Text(model.phase).font(.system(size: 14, weight: .semibold))
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.phase)
                }
                Spacer()
                Text("\(Int(model.percent))%").font(.system(size: 28, weight: .bold)).monospacedDigit()
                    .contentTransition(.numericText(value: model.percent))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: Int(model.percent))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(Paint.blue).frame(width: proxy.size.width * min(1, max(0, model.percent / 100)))
                        .animation(reduceMotion ? nil : .linear(duration: 0.16), value: model.percent)
                }
            }
            .frame(height: 7).padding(.top, 13)
            HStack(spacing: 0) {
                metric(model.queue.map(String.init) ?? "—", "队列")
                Rectangle().fill(Paint.line).frame(width: 1)
                metric(String(model.completed), "已完成")
                Rectangle().fill(Paint.line).frame(width: 1)
                metric(String(model.skipped), "跳过")
            }
            .frame(height: 67)
            .overlay(alignment: .top) { Rectangle().fill(Paint.line).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Paint.line).frame(height: 1) }
            .padding(.top, 16)
            HStack(spacing: 12) {
                BridgeIcon(kind: .music)
                    .frame(width: 18, height: 18).foregroundStyle(Paint.secondary)
                    .frame(width: 34, height: 34)
                    .background(Paint.input, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.taskTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(model.taskDetail).font(.system(size: 11)).foregroundStyle(Paint.secondary).lineLimit(2)
                }
                .offset(x: -1, y: -1.5)
                Spacer(minLength: 0)
            }
            .padding(.top, 21)
        }
        .padding(.horizontal, 23)
        .padding(.top, 19)
        .padding(.bottom, 23)
        .frame(maxWidth: .infinity, minHeight: 234, maxHeight: 234, alignment: .topLeading)
        .floatingSurface()
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 18, weight: .semibold)).monospacedDigit()
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: value)
            Text(label).font(.system(size: 11)).foregroundStyle(Paint.secondary)
        }.frame(maxWidth: .infinity)
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                IPodGlyph().frame(width: 42, height: 64).offset(y: -2)
                Spacer()
                HStack(spacing: 7) {
                    Circle().fill(deviceConnected ? Paint.green : Paint.placeholder).frame(width: 6, height: 6)
                    Text(model.deviceStatus).font(.system(size: 11, weight: .semibold))
                        .contentTransition(.opacity)
                }
                .foregroundStyle(deviceConnected ? Paint.green : Paint.secondary)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background((deviceConnected ? Paint.green : Paint.secondary).opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                .offset(y: -5.5)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.deviceStatus)
            }
            .padding(.top, 2).padding(.leading, 4)
            Text(model.device?.name ?? "iPod 未连接")
                .font(.system(size: 20, weight: .bold)).tracking(-0.5)
                .padding(.top, 20).lineLimit(1)
            Text(model.device.map { $0.isRockbox ? "Rockbox 音乐设备" : "iPod 音乐设备" } ?? "连接 iPod 后可导入音乐")
                .font(.system(size: 13)).foregroundStyle(Paint.secondary).padding(.top, 3)
            Rectangle().fill(Paint.line).frame(height: 1).padding(.top, 19)
            VStack(spacing: 9) {
                deviceRow("文件系统", model.device?.writeState.rawValue ?? "未连接")
                deviceRow("挂载点", model.device?.rootURL.path ?? "—")
                deviceRow("目标目录", "Music/")
            }
            .padding(.vertical, 15)
            Rectangle().fill(Paint.line).frame(height: 1)
            Button { model.importMusic() } label: {
                HStack(spacing: 10) {
                    BridgeIcon(kind: .importMusic).frame(width: 16, height: 16)
                    Text(model.importing ? "正在导入" : "开始导入")
                }
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 46)
            }
            .buttonStyle(BlueButtonStyle())
            .disabled(!model.canImport)
            .padding(.top, 20)
            Text("点击后才扫描下载目录并复制；不会自动导入设备。")
                .font(.system(size: 10.5)).foregroundStyle(Paint.secondary)
                .lineLimit(2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 11)
        }
        .padding(23)
        .frame(maxWidth: .infinity, minHeight: 380, maxHeight: 380, alignment: .topLeading)
        .floatingSurface()
    }

    private var deviceConnected: Bool { model.device?.canImport == true }

    private func deviceRow(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).foregroundStyle(Paint.secondary)
            Spacer()
            Text(value).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
        }.font(.system(size: 12.5))
    }

    private var disclosures: some View {
        VStack(spacing: 0) {
            disclosureHeader("下载设置", detail: "\(model.quality.summary) · \(model.originalCover ? "原始封面" : "不嵌入封面")", expanded: model.settingsExpanded) {
                model.settingsExpanded.toggle()
            }
            if model.settingsExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("下载音质", selection: $model.quality) {
                        ForEach(AudioQuality.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("默认选择最高 ALAC 无损；实际采样率和位深以曲目提供的音源为准。")
                        .foregroundStyle(Paint.secondary)
                    Toggle("嵌入原始封面", isOn: $model.originalCover).tint(Paint.blue)
                    HStack {
                        Text(model.connectionDetail).foregroundStyle(Paint.secondary)
                        Spacer()
                        Button("检查连接") { Task { await model.checkService() } }
                            .disabled(model.checkingService)
                    }
                    Button("在 Finder 中显示下载目录") { NSWorkspace.shared.open(model.root) }
                }
                .font(.system(size: 12)).padding(.horizontal, 20).padding(.bottom, 20)
                .disabled(model.busy || model.importing)
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : -5)))
            }
            Rectangle().fill(Paint.line).frame(height: 1)
            disclosureHeader("运行日志", detail: "\(model.logs.count) 条", expanded: model.logsExpanded) { model.logsExpanded.toggle() }
            if model.logsExpanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(model.logs.enumerated()), id: \.offset) { _, line in Text(line).frame(maxWidth: .infinity, alignment: .leading) }
                    }.textSelection(.enabled)
                }
                .font(.system(size: 12)).foregroundStyle(Paint.secondary)
                .frame(height: 140).padding(.horizontal, 20).padding(.bottom, 20)
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : -5)))
            }
        }
        .floatingSurface()
    }

    private func disclosureHeader(_ title: String, detail: String, expanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Spacer()
                Text(detail).font(.system(size: 11.5)).foregroundStyle(Paint.secondary)
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: detail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Paint.secondary).padding(.leading, 10)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: expanded)
            }.padding(.horizontal, 20).frame(height: 50).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(expanded ? "已展开" : "已收起")
    }
}

private struct BridgeIcon: View {
    enum Kind { case link, download, importMusic, music, stop }
    let kind: Kind
    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width, geometry.size.height) / 24
            Path { path in
                switch kind {
                case .download:
                    path.move(to: CGPoint(x: 12, y: 3)); path.addLine(to: CGPoint(x: 12, y: 15))
                    path.move(to: CGPoint(x: 7, y: 10)); path.addLine(to: CGPoint(x: 12, y: 15)); path.addLine(to: CGPoint(x: 17, y: 10))
                    path.move(to: CGPoint(x: 5, y: 21)); path.addLine(to: CGPoint(x: 19, y: 21))
                case .importMusic:
                    path.move(to: CGPoint(x: 5, y: 3)); path.addLine(to: CGPoint(x: 19, y: 3))
                    path.move(to: CGPoint(x: 12, y: 21)); path.addLine(to: CGPoint(x: 12, y: 9))
                    path.move(to: CGPoint(x: 7, y: 14)); path.addLine(to: CGPoint(x: 12, y: 9)); path.addLine(to: CGPoint(x: 17, y: 14))
                case .link:
                    path.move(to: CGPoint(x: 10, y: 13))
                    path.addCurve(to: CGPoint(x: 17, y: 13), control1: CGPoint(x: 11.8, y: 15), control2: CGPoint(x: 15, y: 15))
                    path.addLine(to: CGPoint(x: 20, y: 10))
                    path.addCurve(to: CGPoint(x: 13, y: 3), control1: CGPoint(x: 24.5, y: 5.5), control2: CGPoint(x: 17.5, y: -1.5))
                    path.addLine(to: CGPoint(x: 11, y: 5))
                    path.move(to: CGPoint(x: 14, y: 11))
                    path.addCurve(to: CGPoint(x: 7, y: 11), control1: CGPoint(x: 12.2, y: 9), control2: CGPoint(x: 9, y: 9))
                    path.addLine(to: CGPoint(x: 4, y: 14))
                    path.addCurve(to: CGPoint(x: 11, y: 21), control1: CGPoint(x: -0.5, y: 18.5), control2: CGPoint(x: 6.5, y: 25.5))
                    path.addLine(to: CGPoint(x: 13, y: 19))
                case .music:
                    path.move(to: CGPoint(x: 9, y: 18)); path.addLine(to: CGPoint(x: 9, y: 5)); path.addLine(to: CGPoint(x: 21, y: 3)); path.addLine(to: CGPoint(x: 21, y: 16))
                    path.move(to: CGPoint(x: 9, y: 9)); path.addLine(to: CGPoint(x: 21, y: 7))
                    path.addEllipse(in: CGRect(x: 3, y: 15, width: 6, height: 6))
                    path.addEllipse(in: CGRect(x: 15, y: 13, width: 6, height: 6))
                case .stop:
                    path.addRoundedRect(in: CGRect(x: 5, y: 5, width: 14, height: 14), cornerSize: CGSize(width: 1, height: 1))
                }
            }
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .stroke(style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

private struct BlueButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var enabled
    func makeBody(configuration: Configuration) -> some View {
        ActionButtonSurface(label: configuration.label, pressed: configuration.isPressed, enabled: enabled)
    }
}

private final class ActionButtonState: ObservableObject {
    @Published var hovered = false
}

private struct ActionButtonSurface<Label: View>: View {
    let label: Label
    let pressed: Bool
    let enabled: Bool
    @StateObject private var state = ActionButtonState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        label.foregroundStyle(Paint.white)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Paint.blue.opacity(enabled ? pressed ? 0.82 : 1 : 0.35))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: [Color.white.opacity(enabled && state.hovered ? 0.12 : 0.035), .clear], startPoint: .top, endPoint: .bottom))
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .scaleEffect(enabled && pressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: state.hovered)
            .onHover { state.hovered = $0 && enabled && activeState != .inactive }
            .onChange(of: enabled) { _, value in if !value { state.hovered = false } }
            .onChange(of: activeState) { _, value in if value == .inactive { state.hovered = false } }
            .onDisappear { state.hovered = false }
    }
}

private struct IPodGlyph: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.11))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.65), lineWidth: 1.4))
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3).fill(Color(red: 102/255, green: 109/255, blue: 117/255)).frame(height: 20)
                ZStack {
                    Circle().fill(Color.white.opacity(0.15)).frame(width: 23, height: 23)
                    Circle().fill(Color.white.opacity(0.35)).frame(width: 7, height: 7)
                    VStack { Capsule().fill(Color.white.opacity(0.45)).frame(width: 4, height: 1); Spacer(); Capsule().fill(Color.white.opacity(0.45)).frame(width: 1, height: 3) }.frame(height: 19)
                    HStack { Capsule().fill(Color.white.opacity(0.45)).frame(width: 3, height: 1); Spacer(); Capsule().fill(Color.white.opacity(0.45)).frame(width: 3, height: 1) }.frame(width: 19)
                }
            }.padding(5)
        }
        .frame(width: 36, height: 59)
        .accessibilityLabel("iPod")
    }
}
