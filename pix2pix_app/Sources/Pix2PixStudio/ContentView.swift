import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            List(SidebarPage.allCases, selection: $state.page) { page in
                Label(page.rawValue, systemImage: page.symbol).tag(page)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 215)
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    HStack(spacing: 8) {
                        if state.isWorking { ProgressView().controlSize(.small) }
                        Circle().fill(state.isWorking ? Color.orange : Color.green).frame(width: 7, height: 7)
                        Text(state.activity).lineLimit(2).font(.caption).foregroundStyle(.secondary)
                    }
                    if let progress = state.progress { ProgressView(value: progress) }
                }
                .padding(12)
            }
        } detail: {
            switch state.page ?? .studio {
            case .studio: StudioView()
            case .downloads: DownloadsView()
            case .files: FilesView()
            }
        }
        .alert("Pix2Pix Studio", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(state.errorMessage ?? "") }
    }
}

private struct StudioView: View {
    @EnvironmentObject private var state: AppState
    @State private var inputMode = 0
    @State private var strokes: [SketchStroke] = []
    @State private var activeStroke: SketchStroke?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pix2Pix Studio").font(.title2.bold())
                    Text("Drop it, sketch it, transform it. Images are center-cropped automatically.").foregroundStyle(.secondary)
                }
                Spacer()
                ModelAndDatasetMenu()
                StatusPill(installed: state.modelStates[state.preset] == true)
            }
            .padding(22)

            Divider()

            HStack(spacing: 18) {
                editorCard(title: "INPUT", subtitle: inputMode == 0 ? "Drop any image here" : "Draw black lines on white") {
                    VStack(spacing: 12) {
                        Picker("Input", selection: $inputMode) {
                            Text("Drop / Open").tag(0)
                            Text("Sketch").tag(1)
                        }.pickerStyle(.segmented).frame(maxWidth: 280)

                        Toggle("Keep whole image · add white margins", isOn: $state.keepWholeImage)
                            .toggleStyle(.checkbox)
                            .onChange(of: state.keepWholeImage) { _ in state.reprepareInput() }
                            .disabled(inputMode == 1)

                        if inputMode == 0 {
                            DropImageView(image: state.inputImage)
                                .onDrop(of: [UTType.image.identifier], isTargeted: nil, perform: state.acceptDrop)
                            HStack {
                                Button("Open Image…") { state.chooseInputImage() }
                                Button("Make Edge Map") { state.prepareEdges() }.disabled(state.inputImage == nil)
                            }
                        } else {
                            SketchPad(strokes: $strokes, activeStroke: $activeStroke)
                            HStack {
                                Button("Clear") { strokes = []; activeStroke = nil }
                                Button("Use Sketch") { state.useSketch(strokes + (activeStroke.map { [$0] } ?? [])) }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                }

                Image(systemName: "arrow.right")
                    .font(.title2.bold()).foregroundStyle(.tertiary)

                editorCard(title: "OUTPUT", subtitle: state.outputURL == nil ? "Your result appears here" : "Drag this image straight to Finder") {
                    VStack(spacing: 12) {
                        ResultImageView(image: state.outputImage, url: state.outputURL)
                        HStack {
                            Button("Save As…") { state.saveResultAs() }.disabled(state.outputURL == nil)
                            Button("Show in Finder") { if let url = state.outputURL { state.reveal(url) } }.disabled(state.outputURL == nil)
                        }
                    }
                }
            }
            .padding(22)

            Divider()
            HStack {
                Label(state.preset.engineLabel, systemImage: state.preset == .cats ? "cpu" : "apple.logo")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("Output", selection: $state.exportSize) {
                    ForEach(ExportSize.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 150)
                if state.modelStates[state.preset] != true {
                    Button("Install \(state.preset.shortTitle) Model") { state.installModel(state.preset) }
                }
                Button {
                    state.generate()
                } label: {
                    Label(state.isWorking ? "Working…" : "Generate", systemImage: "sparkles")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(state.preset.accent)
                .disabled(state.isWorking || state.inputURL == nil)
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func editorCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text(subtitle).font(.caption).foregroundStyle(.tertiary)
            }
            content()
        }
        .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
    }
}

private struct ModelAndDatasetMenu: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Menu {
            Section("Pix2pix models") {
                ForEach(Pix2PixPreset.pix2pixModels) { item in
                    Button {
                        state.preset = item
                    } label: {
                        if state.preset == item { Label(item.title, systemImage: "checkmark") }
                        else { Text(item.title) }
                    }
                }
            }
            Section("CycleGAN models") {
                ForEach(Pix2PixPreset.cycleGANModels) { item in
                    Button {
                        state.preset = item
                    } label: {
                        if state.preset == item { Label(item.title, systemImage: "checkmark") }
                        else { Text(item.title) }
                    }
                }
            }
            Section("Public training datasets") {
                ForEach(DatasetPackage.allCases) { item in
                    Button {
                        state.page = .downloads
                        state.activity = "\(item.title) is in Models & Data"
                    } label: {
                        Text("\(item.title) · \(item.size)")
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(state.preset.title).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 210)
        }
        .menuStyle(.borderlessButton)
        .help("Choose a runnable model or open a public training dataset")
    }
}

private struct DropImageView: View {
    let image: NSImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor))
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(8)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 42)).foregroundStyle(.secondary)
                    Text("Drop an image").font(.headline)
                    Text("PNG · JPEG · TIFF · HEIC").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(minHeight: 330)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style: StrokeStyle(lineWidth: 1.5, dash: [7])).foregroundStyle(.quaternary))
    }
}

private struct ResultImageView: View {
    let image: NSImage?
    let url: URL?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor))
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(8)
                    .onDrag { url.flatMap(NSItemProvider.init(contentsOf:)) ?? NSItemProvider() }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack").font(.system(size: 42)).foregroundStyle(.tertiary)
                    Text("Ready when you are").font(.headline).foregroundStyle(.secondary)
                }
            }
        }
        .frame(minHeight: 370)
    }
}

private struct SketchPad: View {
    @Binding var strokes: [SketchStroke]
    @Binding var activeStroke: SketchStroke?

    var body: some View {
        Canvas { context, _ in
            context.fill(Path(CGRect(x: 0, y: 0, width: 256, height: 256)), with: .color(.white))
            for stroke in strokes + (activeStroke.map { [$0] } ?? []) {
                var path = Path()
                guard let first = stroke.points.first else { continue }
                path.move(to: first)
                for point in stroke.points.dropFirst() { path.addLine(to: point) }
                context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: 256, height: 256)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            if activeStroke == nil { activeStroke = SketchStroke(points: [value.location]) }
            else { activeStroke?.points.append(value.location) }
        }.onEnded { _ in
            if let activeStroke { strokes.append(activeStroke) }
            activeStroke = nil
        })
        .frame(maxHeight: .infinity)
    }
}

private struct DownloadsView: View {
    @EnvironmentObject private var state: AppState
    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Models & Data").font(.largeTitle.bold())
                    Text("No terminal commands and no folder-name typing. Install only what you want.").foregroundStyle(.secondary)
                }
                sectionTitle("PIX2PIX MODELS", detail: "Paired image-to-image models, plus the community Cats model.")
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Pix2PixPreset.pix2pixModels) { item in ModelDownloadCard(item: item) }
                }
                sectionTitle("CYCLEGAN MODELS", detail: "18 official unpaired transformations · roughly 44 MB each · Metal accelerated.")
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Pix2PixPreset.cycleGANModels) { item in ModelDownloadCard(item: item) }
                }
                sectionTitle("PAIRED DATASETS", detail: "Large archives expand into the app’s Data folder.")
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(DatasetPackage.allCases) { item in DatasetDownloadCard(item: item) }
                }
                if !state.log.isEmpty {
                    DisclosureGroup("Installation details") {
                        Text(state.log.suffix(30).joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }
                }
            }.padding(28)
        }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption.bold()).foregroundStyle(.secondary); Text(detail).font(.caption).foregroundStyle(.tertiary) }
    }
}

private struct ModelDownloadCard: View {
    @EnvironmentObject private var state: AppState
    let item: Pix2PixPreset
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.symbol).font(.title2).foregroundStyle(item.accent).frame(width: 36, height: 36).background(item.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.headline)
                Text("\(item.modelSize) · \(item.engineLabel)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if state.modelStates[item] == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            else { Button("Install") { state.installModel(item) }.disabled(state.isWorking) }
        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}

private struct DatasetDownloadCard: View {
    @EnvironmentObject private var state: AppState
    let item: DatasetPackage
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.fill.badge.plus").foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.headline)
                Text("\(item.size) · \(item.sourceName)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if state.datasetStates[item] == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            else { Button(item.buttonLabel) { state.installDataset(item) }.disabled(state.isWorking) }
        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}

private struct FilesView: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Files").font(.largeTitle.bold())
                Text("Everything is kept in ordinary Finder folders you control.").foregroundStyle(.secondary)
            }
            pathCard(title: "Finished Images", symbol: "photo.stack.fill", url: state.outputDirectory) {
                Button("Choose…") { state.chooseOutputFolder() }
                Button("New Folder") { state.createOutputFolder() }
                Button("Open") { state.revealOutputFolder() }.buttonStyle(.borderedProminent)
            }
            pathCard(title: "Models, Data & Runtime", symbol: "internaldrive.fill", url: state.workspace.support) {
                Button("Open in Finder") { state.revealSupportFolder() }
            }
            GroupBox("How dragging works") {
                Label("After generation, grab the output image itself and drag it to Desktop, Finder, Photos, Messages, or another app.", systemImage: "hand.draw.fill")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            Spacer()
        }.padding(28)
    }

    private func pathCard<Actions: View>(title: String, symbol: String, url: URL, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.title).foregroundStyle(.blue).frame(width: 44)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(url.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
            Spacer(); actions()
        }.padding(18).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
    }
}

private struct StatusPill: View {
    let installed: Bool
    var body: some View {
        Label(installed ? "Installed" : "Not installed", systemImage: installed ? "checkmark.circle.fill" : "arrow.down.circle")
            .font(.caption.bold()).foregroundStyle(installed ? Color.green : Color.secondary)
            .padding(.horizontal, 9).padding(.vertical, 5).background(.quaternary, in: Capsule())
    }
}
