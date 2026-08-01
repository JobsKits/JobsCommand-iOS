//
//  ContentView.swift
//  JobsPodBinaryBuilder
//
//  Created by Jobs on 2026年7月30日，星期四.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum WorkspaceTab: String, CaseIterable, Identifiable {
        case dependencies = "依赖闭包"
        case provenance = "最终来源"

        var id: String {
            rawValue
        }
    }

    @ObservedObject var model: AppModel
    @State private var searchText = ""
    @State private var workspaceTab: WorkspaceTab = .dependencies

    private var filteredSpecs: [PodSpecRecord] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false else { return model.localSpecs }
        return model.localSpecs.filter {
            $0.name.localizedCaseInsensitiveContains(keyword) ||
                $0.version.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                sidebar
                    .frame(width: 318)
                Divider()
                workspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 1160, minHeight: 760)
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: nil,
            perform: model.acceptDroppedProviders
        )
        .onChange(of: model.isPrepared) {
            if model.isPrepared {
                workspaceTab = .provenance
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Pod Binary Builder")
                    .font(.system(size: 21, weight: .semibold))
                Text("可追溯的 XCFramework 打包工作台")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            stepBadge(
                number: 1,
                title: "建立索引",
                state: model.localSpecs.isEmpty ? .active : .done
            )
            stepConnector(done: model.localSpecs.isEmpty == false)
            stepBadge(
                number: 2,
                title: "预编译验证",
                state: model.isPrepared
                    ? .done
                    : (model.localSpecs.isEmpty ? .waiting : .active)
            )
            stepConnector(done: model.isPrepared)
            stepBadge(
                number: 3,
                title: "正式打包",
                state: model.stage == .completed
                    ? .done
                    : (model.isPrepared ? .active : .waiting)
            )
            if model.isBusy {
                Text("正在执行")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.10))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 72)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("工作区")
                    .font(.headline)
                directoryControl(
                    title: "本地 Pod 根目录",
                    path: model.rootDirectoryPath,
                    emptyText: "尚未导入 JobsByPods",
                    actionTitle: model.localSpecs.isEmpty ? "选择并扫描" : "更换目录",
                    action: model.chooseRootDirectory
                )
                directoryControl(
                    title: "产物输出目录",
                    path: model.outputDirectoryPath,
                    emptyText: "尚未选择输出目录",
                    actionTitle: "更改",
                    action: model.chooseOutputDirectory
                )
            }
            .padding(18)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("选择主 Pod")
                        .font(.headline)
                    Spacer()
                    Text("\(model.localSpecs.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.10))
                        .clipShape(Capsule())
                }

                TextField("按名称或版本筛选", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                if model.localSpecs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("等待本地索引")
                            .font(.subheadline.weight(.semibold))
                        Text("扫描后，Pod 名会在这里形成唯一索引；选中的模块才会进入依赖解析。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(filteredSpecs) { spec in
                                Button {
                                    model.selectRoot(spec.name)
                                } label: {
                                    podRow(spec)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(18)
        }
        .background(
            Color(nsColor: .windowBackgroundColor)
                .overlay(Color.primary.opacity(0.035))
        )
    }

    private var workspace: some View {
        VStack(spacing: 14) {
            statusCard
            if model.localSpecs.isEmpty {
                emptyWorkspace
            } else {
                graphWorkspace
            }
            bottomBar
            logCard
                .frame(height: 182)
        }
        .padding(18)
    }

    private var statusCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(model.stage.title)
                        .font(.system(size: 17, weight: .semibold))
                    if model.unresolvedCount > 0 {
                        metricPill(
                            "\(model.unresolvedCount) 项待处理",
                            color: .orange
                        )
                    } else if model.selectedRootName.isEmpty == false {
                        metricPill("来源已闭环", color: .green)
                    }
                }
                Text(model.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 7) {
                HStack(spacing: 6) {
                    metricPill("本地 \(model.localSpecs.count)", color: .blue)
                    metricPill(
                        model.selectedRootName.isEmpty
                            ? "未选主 Pod"
                            : model.selectedRootName,
                        color: .purple
                    )
                }
                ProgressView(value: model.overallProgress)
                    .frame(width: 260)
            }
        }
        .padding(16)
        .cardSurface()
    }

    private var emptyWorkspace: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("把 JobsByPods 交给我")
                .font(.system(size: 24, weight: .semibold))
            Text("整个目录可以直接拖到这个区域。扫描只建立索引，真正构建时只处理你选择的主 Pod 依赖链。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            Button("选择 JobsByPods 并开始扫描") {
                model.chooseRootDirectory()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Text("本地唯一匹配自动绑定 · 本地同名立即阻断 · 本地缺失必须人工仲裁")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1.5, dash: [8, 7])
                )
        }
    }

    private var graphWorkspace: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        workspaceTab == .dependencies
                            ? "依赖闭包"
                            : "最终来源与交付方式"
                    )
                    .font(.headline)
                    Text(workspaceSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isPrepared {
                    Picker("工作区内容", selection: $workspaceTab) {
                        ForEach(WorkspaceTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }
            }
            .padding(16)

            Divider()

            Group {
                if workspaceTab == .provenance, model.isPrepared {
                    provenanceTable
                } else {
                    dependencyTable
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .cardSurface()
    }

    private var dependencyTable: some View {
        VStack(spacing: 0) {
            dependencyHeader
            Divider()
            if model.selectedRootName.isEmpty {
                compactEmptyState(
                    title: "先选择主 Pod",
                    detail: "左侧选中一个模块后，这里只展示它实际涉及的依赖链。"
                )
            } else if model.resolutionRows.isEmpty {
                compactEmptyState(
                    title: "没有其它 Pod 依赖",
                    detail: "\(model.selectedRootName) 可以直接进入预编译验证。"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.resolutionRows) { row in
                            dependencyRow(row)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var dependencyHeader: some View {
        HStack(spacing: 12) {
            tableHeader("依赖", width: 165)
            tableHeader("依赖方与约束", width: 165)
            tableHeader("状态与来源")
            tableHeader("处理", width: 215)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.035))
    }

    private func dependencyRow(_ row: DependencyResolutionRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.dependency.rootName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if row.dependency.name != row.dependency.rootName {
                    Text(row.dependency.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 165, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.dependency.requestedBy)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(
                    row.dependency.requirement.isEmpty
                        ? "未限定版本"
                        : row.dependency.requirement
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(width: 165, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.state.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stateColor(row.state))
                Text(row.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .help(row.detail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            rowActions(row)
                .frame(width: 215, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func rowActions(_ row: DependencyResolutionRow) -> some View {
        HStack(spacing: 7) {
            if row.state == .unresolved {
                Button("查 CocoaPods") {
                    Task {
                        await model.queryRemote(for: row)
                    }
                }
                Button("选本地") {
                    Task {
                        await model.chooseLocal(for: row)
                    }
                }
            } else if row.state == .versionConflict {
                Text("修改约束或版本后重新扫描")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("无需干预")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var provenanceTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                tableHeader("模块", width: 160)
                tableHeader("版本 / 关系", width: 145)
                tableHeader("来源")
                tableHeader("交付 / 许可证", width: 185)
                tableHeader("指纹", width: 105)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.035))
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.provenanceRows) { row in
                        HStack(spacing: 12) {
                            Text(row.name)
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 160, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.version)
                                Text(row.relationship)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 145, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.sourceType)
                                    .font(.caption.weight(.semibold))
                                Text(row.sourceIdentity)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(row.sourceIdentity)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.packagingMode)
                                Text(row.license)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 185, alignment: .leading)
                            Text(String(row.fingerprint.prefix(10)))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 105, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        Divider()
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if model.isBusy {
                Button("取消当前任务", role: .destructive) {
                    model.cancelCurrentTask()
                }
            } else {
                Button("重新扫描") {
                    Task {
                        await model.scanLocalPods()
                    }
                }
                .disabled(model.canScan == false)
            }

            if model.warningMessages.isEmpty == false {
                metricPill(
                    "\(model.warningMessages.count) 条扫描警告",
                    color: .orange
                )
                .help(model.warningMessages.joined(separator: "\n"))
            }

            Spacer()

            if model.isPrepared {
                Text("已通过双 SDK 预编译并冻结来源")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button("预编译验证") {
                Task {
                    await model.prepareBuild()
                }
            }
            .disabled(model.canPrepare == false)
            .keyboardShortcut("v", modifiers: [.command])

            Button("核对来源并正式打包") {
                Task {
                    await model.confirmAndPackage()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.canPackage == false)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var logCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("实时构建日志")
                    .font(.subheadline.weight(.semibold))
                if model.isBusy {
                    Text(model.stage.title)
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                Spacer()
                if model.finalOutputPath.isEmpty == false {
                    Text(model.finalOutputPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(model.finalOutputPath)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    Text(model.logText.isEmpty ? "等待任务开始…" : model.logText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(model.logText.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .id("LOG_END")
                }
                .onChange(of: model.logText) {
                    proxy.scrollTo("LOG_END", anchor: .bottom)
                }
            }
        }
        .cardSurface()
    }

    private func directoryControl(
        title: String,
        path: String,
        emptyText: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(actionTitle, action: action)
                    .buttonStyle(.link)
                    .disabled(model.isBusy)
            }
            Text(path.isEmpty ? emptyText : compactPath(path))
                .font(.subheadline)
                .foregroundStyle(path.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(path)
        }
    }

    private func podRow(_ spec: PodSpecRecord) -> some View {
        let selected = model.selectedRootName == spec.name
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(selected ? Color.accentColor : Color.secondary.opacity(0.25))
                .frame(width: 4, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(spec.name)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(spec.sourceKind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(spec.version)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selected ? Color.accentColor.opacity(0.11) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }

    private func compactEmptyState(title: String, detail: String) -> some View {
        VStack(spacing: 7) {
            Spacer()
            Text(title)
                .font(.system(size: 18, weight: .semibold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tableHeader(_ text: String, width: CGFloat? = nil) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(
                minWidth: width,
                maxWidth: width == nil ? .infinity : width,
                alignment: .leading
            )
    }

    private func metricPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
    }

    private func stateColor(_ state: DependencyResolutionState) -> Color {
        switch state {
        /// 本地来源已经自动绑定
        case .resolvedLocal:
            return .green
        /// 用户已经确认远程来源
        case .resolvedRemote:
            return .blue
        /// 依赖需要人工判断来源
        case .unresolved:
            return .orange
        /// 已存在来源但版本约束不匹配
        case .versionConflict:
            return .red
        }
    }

    private var workspaceSubtitle: String {
        guard model.selectedRootName.isEmpty == false else {
            return "从左侧选择需要打包的主 Pod"
        }
        if workspaceTab == .provenance {
            return "预编译通过后生成；正式打包前还会再次核对指纹"
        }
        return "\(model.selectedRootName) · 只展示实际传递依赖，不处理目录内无关 Pod"
    }

    private func compactPath(_ path: String) -> String {
        let components = URL(fileURLWithPath: path).pathComponents
        guard components.count > 3 else { return path }
        return "…/" + components.suffix(3).joined(separator: "/")
    }

    private enum StepState {
        case active
        case done
        case waiting
    }

    private func stepBadge(
        number: Int,
        title: String,
        state: StepState
    ) -> some View {
        let active = state == .active
        let done = state == .done
        let color: Color = active || done ? .accentColor : .secondary
        return HStack(spacing: 7) {
            Text(done ? "✓" : "\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(active || done ? .white : color)
                .frame(width: 24, height: 24)
                .background(active || done ? color : color.opacity(0.12))
                .clipShape(Circle())
            Text(title)
                .font(.subheadline.weight(active ? .semibold : .regular))
                .foregroundStyle(active || done ? .primary : .secondary)
        }
    }

    private func stepConnector(done: Bool) -> some View {
        Rectangle()
            .fill(done ? Color.accentColor : Color.secondary.opacity(0.20))
            .frame(width: 34, height: 1)
    }
}

private extension View {
    // 统一工作台卡片的边界、背景和轻量阴影。
    func cardSurface() -> some View {
        background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 8, y: 2)
    }
}
