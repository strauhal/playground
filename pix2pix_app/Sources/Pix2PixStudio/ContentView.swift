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
            case .nextFrame: NextFrameView()
            case .styleGAN2: StyleGANView()
            case .downloads: DownloadsView()
            case .files: FilesView()
            }
        }
        .alert("Pix2Pix Studio", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(state.errorMessage ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            state.stopAllWork()
        }
    }
}

private struct StyleGANView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("StyleGAN2 Studio").font(.title2.bold())
                    Text("Generate latent journeys, project footage, or fine-tune a model from your own videos.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(installed: state.selectedStyleGANModelURL != nil)
            }
            .padding(22)

            Divider()

            ScrollView {
                VStack(spacing: 18) {
                    HStack(spacing: 12) {
                        Picker("World", selection: Binding(
                            get: { state.styleGANPreset },
                            set: { state.selectOfficialStyleGANPreset($0) }
                        )) {
                            ForEach(StyleGANPreset.allCases) { Text($0.title).tag($0) }
                        }
                        .frame(width: 235)
                        .disabled(state.isWorking)

                        Picker("Checkpoint", selection: Binding<URL?>(
                            get: { state.selectedStyleGANModelURL },
                            set: { state.selectStyleGANModel($0) }
                        )) {
                            Text("Choose a checkpoint").tag(Optional<URL>.none)
                            ForEach(state.styleGANModels, id: \.self) { url in
                                Text(state.styleGANModelDisplayName(url)).tag(Optional(url))
                            }
                        }
                        .frame(width: 245)
                        .disabled(state.isWorking || state.styleGANModels.isEmpty)

                        Text("Native \(state.styleGANPreset.nativeResolution) px · \(state.styleGANPreset.modelSize)")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if state.styleGANModelStates[state.styleGANPreset] != true {
                            Button {
                                state.installStyleGANModel(state.styleGANPreset)
                            } label: {
                                Label("Download Model", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.borderedProminent).tint(.purple)
                            .disabled(state.isWorking)
                        }
                        Button { state.revealStyleGANModels() } label: {
                            Label("View Models in Finder", systemImage: "folder")
                        }
                        .disabled(state.isWorking)
                    }
                    .padding(14)
                    .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))

                    Picker("Mode", selection: $state.styleGANMode) {
                        ForEach(StyleGANMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 440)
                    .disabled(state.isWorking)

                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Text(sourceTitle)
                                    .font(.caption.bold()).foregroundStyle(.secondary)
                                Spacer()
                                Text(sourceSubtitle)
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                            if state.styleGANMode == .video {
                                DropVideoView(image: state.styleGANVideoThumbnail, name: state.styleGANVideoURL?.lastPathComponent)
                                    .onDrop(of: [UTType.fileURL.identifier, UTType.item.identifier, UTType.data.identifier], isTargeted: nil, perform: state.acceptStyleGANVideoDrop)
                                Button("Choose Any Video…") { state.chooseStyleGANVideo() }.disabled(state.isWorking)
                            } else if state.styleGANMode == .training {
                                DropVideoView(
                                    image: state.styleGANVideoThumbnail,
                                    name: state.styleGANTrainingVideos.isEmpty ? nil : "\(state.styleGANTrainingVideos.count) source video\(state.styleGANTrainingVideos.count == 1 ? "" : "s")"
                                )
                                .onDrop(of: [UTType.fileURL.identifier, UTType.item.identifier, UTType.data.identifier], isTargeted: nil, perform: state.acceptStyleGANTrainingVideoDrop)
                                HStack {
                                    Button("Choose Videos…") { state.chooseStyleGANTrainingVideos() }.disabled(state.isWorking)
                                    Button("Clear") { state.clearStyleGANTrainingVideos() }
                                        .disabled(state.isWorking || state.styleGANTrainingVideos.isEmpty)
                                    Button("View Extracted Frames") { state.revealStyleGANDatasets() }
                                }
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor))
                                    VStack(spacing: 12) {
                                        Image(systemName: "point.3.connected.trianglepath.dotted")
                                            .font(.system(size: 48)).foregroundStyle(.purple)
                                        Text("Random latent coordinates").font(.headline)
                                        Text("No source file needed").font(.caption).foregroundStyle(.secondary)
                                    }
                                }.frame(minHeight: 250)
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))

                        Image(systemName: "arrow.right").font(.title2.bold()).foregroundStyle(.tertiary)

                        VStack(alignment: .leading, spacing: 11) {
                            HStack {
                                Text(state.styleGANMode == .training ? "TRAINING PREVIEW" : "LATEST FRAME").font(.caption.bold()).foregroundStyle(.secondary)
                                Spacer()
                                if state.isStyleGANRunning {
                                    Text(styleGANProgressText)
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            ResultImageView(image: state.outputImage, url: state.outputURL)
                                .frame(minHeight: 250)
                            HStack {
                                Button("Open StyleGAN2 Output") { state.revealStyleGANOutput() }
                                Button("Show Latest Frame") {
                                    if let url = state.outputURL { state.reveal(url) }
                                }.disabled(state.outputURL == nil)
                                Button("Show Movie") {
                                    if let url = state.styleGANOutputVideoURL { state.reveal(url) }
                                }.disabled(state.styleGANOutputVideoURL == nil || state.styleGANMode == .training)
                            }
                        }
                        .padding(16).frame(maxWidth: .infinity)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
                    }

                    HStack(alignment: .top, spacing: 14) {
                        GroupBox("Journey") {
                            VStack(alignment: .leading, spacing: 12) {
                                if state.styleGANMode == .latent {
                                    labeledField("Keyframes", value: $state.styleGANKeyframes, width: 62)
                                    labeledField("Frames per transition", value: $state.styleGANTransitionFrames, width: 68)
                                    labeledField("Frames per second", value: $state.styleGANFPS, width: 62)
                                    Picker("Interpolation", selection: $state.styleGANInterpolation) {
                                        ForEach(StyleGANInterpolation.allCases) { Text($0.rawValue).tag($0) }
                                    }
                                    Toggle("Seamless loop", isOn: $state.styleGANLoop).toggleStyle(.checkbox)
                                } else if state.styleGANMode == .video {
                                    labeledField("Video samples", value: $state.styleGANVideoKeyframes, width: 62)
                                    labeledField("Projection steps", value: $state.styleGANProjectionSteps, width: 68)
                                    Picker("Frame fitting", selection: $state.styleGANVideoFit) {
                                        ForEach(StyleGANVideoFit.allCases) { Text($0.rawValue).tag($0) }
                                    }
                                    labeledField("Frames per transition", value: $state.styleGANTransitionFrames, width: 68)
                                    labeledField("Frames per second", value: $state.styleGANFPS, width: 62)
                                    Picker("Interpolation", selection: $state.styleGANInterpolation) {
                                        ForEach(StyleGANInterpolation.allCases) { Text($0.rawValue).tag($0) }
                                    }
                                    Toggle("Seamless loop", isOn: $state.styleGANLoop).toggleStyle(.checkbox)
                                } else {
                                    Picker("Training speed", selection: $state.styleGANTrainingSize) {
                                        ForEach(StyleGANTrainingSize.allCases) { Text($0.title).tag($0) }
                                    }
                                    labeledField("Maximum source frames", value: $state.styleGANTrainingMaxFrames, width: 72)
                                    labeledField("Use every nth frame", value: $state.styleGANTrainingFrameStep, width: 62)
                                    labeledField("Epochs", value: $state.styleGANTrainingEpochs, width: 62)
                                    Picker("Frame fitting", selection: $state.styleGANVideoFit) {
                                        ForEach(StyleGANVideoFit.allCases) { Text($0.rawValue).tag($0) }
                                    }
                                }
                            }.padding(8)
                        }

                        GroupBox(state.styleGANMode == .training ? "Training" : "Latent Space") {
                            VStack(alignment: .leading, spacing: 12) {
                                if state.styleGANMode == .training {
                                    labeledField("Batch size", value: $state.styleGANTrainingBatchSize, width: 62)
                                    labeledField("Learning rate", value: $state.styleGANTrainingLearningRate, width: 86)
                                    Toggle("Training augmentation", isOn: $state.styleGANTrainingAugment).toggleStyle(.checkbox)
                                    Text("Augmentation helps smaller collections of video frames overfit less quickly.")
                                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                } else {
                                    sliderRow("Travel distance", value: $state.styleGANDistance, range: 0...4)
                                    sliderRow("Truncation", value: $state.styleGANTruncation, range: 0...2)
                                    Picker("Texture noise", selection: $state.styleGANNoise) {
                                        ForEach(StyleGANNoiseMode.allCases) { Text($0.rawValue).tag($0) }
                                    }
                                    labeledField("Random seed", value: $state.styleGANSeed, width: 80)
                                }
                                if state.styleGANPreset == .cifar10 {
                                    Picker("CIFAR class", selection: $state.styleGANClassIndex) {
                                        ForEach(0..<10, id: \.self) { Text("Class \($0)").tag($0) }
                                    }
                                }
                            }.padding(8)
                        }

                        GroupBox(state.styleGANMode == .training ? "Save Model" : "Style Mixing") {
                            VStack(alignment: .leading, spacing: 12) {
                                if state.styleGANMode == .training {
                                    TextField("Model name", text: $state.styleGANTrainingName).textFieldStyle(.roundedBorder)
                                    Text("Training starts from the selected checkpoint. The finished model is saved in Models and selected automatically.")
                                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    if state.styleGANPreset.nativeResolution >= 512 {
                                        Label("512–1024 px training is demanding. Start with a small frame set and one epoch.", systemImage: "exclamationmark.triangle")
                                            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                                    }
                                } else {
                                    sliderRow("Mix amount", value: $state.styleGANStyleMix, range: 0...1)
                                    labeledField("Layer cutoff", value: $state.styleGANStyleCutoff, width: 62)
                                    Text("A second latent can supply later layers—usually color and fine texture—while early layers retain structure.")
                                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                }
                            }.padding(8)
                        }
                    }
                    .disabled(state.isWorking)

                    if state.styleGANMode == .video {
                        Label("Projection is domain-specific: footage is automatically fitted, but FFHQ interprets every frame as a face, AFHQ as an animal, and so on.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if state.styleGANMode == .training {
                        Label("This fine-tunes the selected visual world from all chosen videos. Source frames are sampled automatically and kept with the training previews.", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(22)
            }

            Divider()
            HStack(spacing: 12) {
                Label("Official NVIDIA StyleGAN2-ADA · PyTorch · Metal when supported", systemImage: "apple.logo")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if state.styleGANMode != .training {
                    Picker("Output", selection: $state.exportSize) {
                        ForEach(ExportSize.allCases) { Text($0.label).tag($0) }
                    }.frame(width: 150).disabled(state.isWorking)
                }
                if state.isStyleGANRunning {
                    Button(role: .destructive) { state.stopStyleGAN() } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }.controlSize(.large)
                }
                Button { state.runStyleGAN() } label: {
                    Label(styleGANActionLabel, systemImage: state.styleGANMode == .training ? "brain.head.profile" : "sparkles.tv")
                        .frame(minWidth: 145)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(.purple)
                .disabled(state.isWorking || state.selectedStyleGANModelURL == nil || (state.styleGANMode == .video && state.styleGANVideoURL == nil) || (state.styleGANMode == .training && state.styleGANTrainingVideos.isEmpty))
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func labeledField(_ label: String, value: Binding<Int>, width: CGFloat) -> some View {
        HStack { Text(label); Spacer(); TextField(label, value: value, format: .number).textFieldStyle(.roundedBorder).frame(width: width) }
    }

    private func labeledField(_ label: String, value: Binding<Double>, width: CGFloat) -> some View {
        HStack { Text(label); Spacer(); TextField(label, value: value, format: .number).textFieldStyle(.roundedBorder).frame(width: width) }
    }

    private var sourceTitle: String {
        switch state.styleGANMode { case .latent: return "LATENT SOURCE"; case .video: return "SOURCE VIDEO"; case .training: return "TRAINING VIDEOS" }
    }

    private var sourceSubtitle: String {
        switch state.styleGANMode { case .latent: return "Seeded and repeatable"; case .video: return "No manual cropping required"; case .training: return "Drop one or many videos" }
    }

    private var styleGANProgressText: String {
        if state.styleGANMode == .training {
            return state.totalStyleGANTrainingSteps > 0 ? "\(state.completedStyleGANTrainingSteps) / \(state.totalStyleGANTrainingSteps)" : "Preparing frames…"
        }
        return "\(state.completedStyleGANFrames) / \(max(state.totalStyleGANFrames, 1))"
    }

    private var styleGANActionLabel: String {
        if state.styleGANMode == .training { return state.isStyleGANRunning ? "Training…" : "Train Model" }
        return state.isStyleGANRunning ? "Rendering…" : "Create Animation"
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(label); Spacer(); Text(value.wrappedValue, format: .number.precision(.fractionLength(2))).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range, step: 0.05)
        }
    }
}

private struct DropVideoView: View {
    let image: NSImage?
    let name: String?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor))
            if let image {
                Image(nsImage: image).resizable().scaledToFit().padding(8)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "film.badge.plus").font(.system(size: 44)).foregroundStyle(.purple)
                    Text(name ?? "Drop any video").font(.headline).lineLimit(1)
                    Text("MOV · MP4 · M4V · MKV · AVI · WebM and other FFmpeg formats")
                        .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }.padding()
            }
        }
        .frame(minHeight: 250)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(style: StrokeStyle(lineWidth: 1.5, dash: [7])).foregroundStyle(.quaternary))
    }
}

private struct NextFrameView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next Frame Prediction").font(.title2.bold())
                    Text("Schultz-style NFP: learn frame t → frame t+1 from a video, then recursively predict from a seed image.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(installed: state.nfpModelInstalled)
            }
            .padding(22)

            Divider()

            HStack(spacing: 12) {
                Image(systemName: "video.badge.plus").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRAIN FROM CONSECUTIVE VIDEO FRAMES").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(state.nfpTrainingVideoURL?.lastPathComponent ?? "Choose a simple, repeating source video—fire, water, clouds, traffic, and similar motion work well.")
                        .lineLimit(1).foregroundStyle(state.nfpTrainingVideoURL == nil ? .secondary : .primary)
                }
                Spacer()
                Button("Choose Video…") { state.chooseNFPTrainingVideo() }.disabled(state.isWorking)
                Picker("Choose Model", selection: Binding(
                    get: { state.selectedNFPModelURL },
                    set: { state.selectNFPModel($0) }
                )) {
                    if state.nfpModels.isEmpty {
                        Text("No Trained Models").tag(URL?.none)
                    } else {
                        ForEach(state.nfpModels, id: \.self) { url in
                            Text(state.nfpModelDisplayName(url)).tag(Optional(url))
                        }
                    }
                }
                .frame(width: 210)
                .disabled(state.isWorking || state.nfpModels.isEmpty)
                Button {
                    state.revealNFPModelsFolder()
                } label: {
                    Label("View Models in Finder", systemImage: "folder")
                }
                .disabled(state.isWorking)
                TextField("Frames", value: $state.nfpMaxTrainingFrames, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 72).disabled(state.isWorking)
                Text("source frames").font(.caption).foregroundStyle(.secondary)
                TextField("Epochs", value: $state.nfpEpochs, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 60).disabled(state.isWorking)
                Text("epochs").font(.caption).foregroundStyle(.secondary)
                if state.isNFPTraining {
                    Button(role: .destructive) { state.stopNFP() } label: { Label("Stop", systemImage: "stop.fill") }
                }
                Button {
                    state.trainNFPModel()
                } label: {
                    Label(state.isNFPTraining ? "Training…" : (state.nfpModelInstalled ? "Retrain Model" : "Train Model"), systemImage: "brain.head.profile")
                }
                .buttonStyle(.borderedProminent).tint(.orange)
                .disabled(state.isWorking || state.nfpTrainingVideoURL == nil)
            }
            .padding(14)
            .background(Color.orange.opacity(0.06))

            Divider()

            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("STARTING FRAME").font(.caption.bold()).foregroundStyle(.secondary)
                        Spacer()
                        Text("Drop an image to begin").font(.caption).foregroundStyle(.tertiary)
                    }
                    DropImageView(image: state.inputImage)
                        .onDrop(of: [UTType.image.identifier], isTargeted: nil, perform: state.acceptDrop)
                    Button("Open Starting Frame…") { state.chooseInputImage() }
                        .disabled(state.isWorking)
                }
                .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))

                Image(systemName: "arrow.right").font(.title2.bold()).foregroundStyle(.tertiary)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("LATEST PREDICTION").font(.caption.bold()).foregroundStyle(.secondary)
                        Spacer()
                        if state.isNFPPredicting {
                            Text("\(state.completedNFPFrames) / \(max(state.nfpFrameCount, 1))")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    ResultImageView(image: state.outputImage, url: state.outputURL)
                    HStack {
                        Button("Open Frames") { state.revealFramesFolder() }
                        Button("Show Latest in Finder") {
                            if let url = state.outputURL { state.reveal(url) }
                        }.disabled(state.outputURL == nil)
                    }
                }
                .padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
            }
            .padding(22)

            Divider()
            HStack(spacing: 12) {
                Label("Direct image prediction · no edge maps", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                TextField("Frames", value: $state.nfpFrameCount, format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 72)
                    .disabled(state.isWorking)
                Text("frames").font(.caption).foregroundStyle(.secondary)
                Picker("Output", selection: $state.exportSize) {
                    ForEach(ExportSize.allCases) { Text($0.label).tag($0) }
                }.frame(width: 150).disabled(state.isWorking)
                Toggle("Anchor to starting frame", isOn: $state.nfpAnchorToStartingFrame)
                    .toggleStyle(.checkbox)
                    .disabled(state.isWorking)
                    .help("Guides each prediction with the starting frame without overlaying it on the output")
                if state.isNFPPredicting {
                    Button(role: .destructive) { state.stopNFP() } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }.controlSize(.large)
                }
                Button {
                    state.predictNextFrames()
                } label: {
                    Label(state.isNFPPredicting ? "Predicting…" : "Predict Frames", systemImage: "film.stack")
                        .frame(minWidth: 125)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(.orange)
                .disabled(state.isWorking || state.inputURL == nil || !state.nfpModelInstalled)
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
                Toggle("Animation", isOn: $state.animationEnabled)
                    .toggleStyle(.checkbox)
                    .disabled(state.isWorking)
                if state.animationEnabled {
                    TextField("Frames", value: $state.animationSteps, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 62)
                        .disabled(state.isWorking)
                    Text("frames").font(.caption).foregroundStyle(.secondary)
                    Button("Open Frames") { state.revealFramesFolder() }
                    if state.isAnimating {
                        Button(role: .destructive) { state.stopAnimation() } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                    }
                }
                Picker("Output", selection: $state.exportSize) {
                    ForEach(ExportSize.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 150)
                if state.modelStates[state.preset] != true {
                    Button("Install \(state.preset.shortTitle) Model") { state.installModel(state.preset) }
                }
                Button {
                    if state.animationEnabled { state.startAnimation() }
                    else { state.generate() }
                } label: {
                    Label(state.isWorking ? "Working…" : (state.animationEnabled ? "Start Animation" : "Generate"), systemImage: state.animationEnabled ? "film.stack" : "sparkles")
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
                sectionTitle("STYLEGAN2-ADA MODELS", detail: "Official NVIDIA generative models for latent journeys, style mixing, and automatic video projection.")
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(StyleGANPreset.allCases) { item in StyleGANDownloadCard(item: item) }
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

private struct StyleGANDownloadCard: View {
    @EnvironmentObject private var state: AppState
    let item: StyleGANPreset
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.symbol).font(.title2).foregroundStyle(.purple).frame(width: 36, height: 36).background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.headline)
                Text("\(item.modelSize) · native \(item.nativeResolution) px").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if state.styleGANModelStates[item] == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            else { Button("Install") { state.installStyleGANModel(item) }.disabled(state.isWorking) }
        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
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
            pathCard(title: "Animation Frames", symbol: "film.stack.fill", url: state.workspace.frames) {
                Button("Open Frames") { state.revealFramesFolder() }.buttonStyle(.borderedProminent)
            }
            pathCard(title: "StyleGAN2 Animations", symbol: "point.3.connected.trianglepath.dotted", url: state.workspace.styleGANOutput) {
                Button("Open Output") { state.revealStyleGANOutput() }.buttonStyle(.borderedProminent)
                Button("Open Models") { state.revealStyleGANModels() }
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
