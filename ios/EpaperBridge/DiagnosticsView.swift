import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject var receiver: BLEReceiver
    @ObservedObject var writer: NFCWriter
    @Binding var selectedTab: Int

    @State private var selectedPattern = 0 // 0: 邊框對齊, 1: 50%網點, 2: 文字解析度, 3: 全黑, 4: 全白
    @State private var patternPreview: UIImage?
    @State private var patternFrame: Data?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Diagnostic Patterns Section
                VStack(alignment: .leading, spacing: 14) {
                    Label("面板品質與校準測試圖", systemImage: "checkerboard.rectangle")
                        .font(.headline)

                    Picker("測試圖類型", selection: $selectedPattern) {
                        Text("邊界對齊").tag(0)
                        Text("50%網點").tag(1)
                        Text("解析度").tag(2)
                        Text("全黑").tag(3)
                        Text("全白").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPattern) { _ in
                        generateSelectedPattern()
                    }

                    if let patternPreview {
                        Image(uiImage: patternPreview)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                            .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)

                        Button {
                            if let patternFrame {
                                receiver.frame = patternFrame
                                receiver.image = patternPreview
                                selectedTab = 0
                            }
                        } label: {
                            Label("載入此測試圖至主畫面更新", systemImage: "arrow.up.circle.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)

                // NFC Performance & Transmission Diagnostics Section
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("最近一次 NFC 通訊診斷", systemImage: "gauge.with.needle.fill")
                            .font(.headline)
                        Spacer()
                        if let diag = writer.diagnostics {
                            Text(diag.finalResult)
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.2))
                                .foregroundStyle(.green)
                                .clipShape(Capsule())
                        }
                    }

                    if let diag = writer.diagnostics {
                        VStack(spacing: 10) {
                            diagRow(title: "硬體型號", value: diag.modelName)
                            diagRow(title: "對位充飽耗時", value: String(format: "%.2f 秒", diag.alignmentDuration))
                            diagRow(title: "400包資料寫入耗時", value: String(format: "%.2f 秒", diag.transmissionDuration))
                            diagRow(title: "刷新輪詢等待耗時", value: String(format: "%.2f 秒", diag.refreshDuration))
                            diagRow(title: "單包發送間隔", value: String(format: "%.1f ms (高速最佳化)", diag.packetIntervalMs))
                            diagRow(title: "更新時間戳記", value: diag.timestamp.formatted(date: .omitted, time: .standard))
                        }
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text("尚未有本次連線的傳輸統計紀錄，執行「更新電子紙」後將自動生成診斷數據。")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)

                // RF Positioning Tool
                VStack(alignment: .leading, spacing: 12) {
                    Label("RF 射頻最佳對位測試", systemImage: "wave.3.forward")
                        .font(.headline)
                    Text("不傳送任何圖片，純粹即時探測線圈強度並以震動輔助確認位置。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        receiver.stop()
                        writer.startAlignmentTest()
                    } label: {
                        Label("立即啟動感應對位測試", systemImage: "antenna.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(writer.busy)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("檢測與診斷")
        .onAppear {
            if patternPreview == nil {
                generateSelectedPattern()
            }
        }
    }

    private func diagRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospaced())
        }
    }

    private func generateSelectedPattern() {
        switch selectedPattern {
        case 0:
            let data = ImageProcessor.testPatternBorderGrid()
            patternFrame = data
            patternPreview = Frame.preview(data)
        case 1:
            let data = ImageProcessor.testPatternCheckerboard()
            patternFrame = data
            patternPreview = Frame.preview(data)
        case 2:
            let img = ImageProcessor.testPatternResolution()
            let data = ImageProcessor.binarize(image: img, threshold: 140)
            patternFrame = data
            patternPreview = Frame.preview(data)
        case 3:
            let data = Data(repeating: 0x00, count: Frame.byteCount) // All Black
            patternFrame = data
            patternPreview = Frame.preview(data)
        case 4:
            let data = Data(repeating: 0xff, count: Frame.byteCount) // All White
            patternFrame = data
            patternPreview = Frame.preview(data)
        default:
            break
        }
    }
}
