import SwiftUI

struct DashboardView: View {
    @ObservedObject var receiver: BLEReceiver
    @ObservedObject var writer: NFCWriter

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Preview Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("畫面預覽", systemImage: "photo.fill")
                            .font(.headline)
                        Spacer()
                        Text("800 × 480 · 1-bit")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
                    }

                    if let image = receiver.image {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.08))
                            .aspectRatio(5.0 / 3.0, contentMode: .fit)
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                    Text("尚未載入圖片")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            )
                    }
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)

                // Live Signal Gauge Card (if busy or tested)
                if writer.busy {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("NFC 對位訊號與進度", systemImage: "antenna.radiowaves.left.and.right")
                                .font(.headline)
                            Spacer()
                            Text(writer.currentScore > 0 ? "\(writer.currentScore)%" : "\(Int(writer.progress * 100))%")
                                .font(.subheadline.bold())
                                .foregroundStyle(writer.currentScore >= 90 ? .green : .accentColor)
                        }

                        ProgressView(value: writer.currentScore > 0 ? Double(writer.currentScore) / 100.0 : writer.progress)
                            .tint(writer.currentScore >= 90 ? .green : .accentColor)

                        Text(writer.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
                }

                // Control Actions Card
                VStack(spacing: 14) {
                    // Computer Bridge Section
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("電腦快速傳圖")
                                .font(.headline)
                            Text(receiver.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(receiver.receiving ? "停止接收" : "接收電腦圖片") {
                            if receiver.receiving { receiver.stop() }
                            else { receiver.start() }
                        }
                        .buttonStyle(.bordered)
                        .tint(receiver.receiving ? .red : .accentColor)
                        .disabled(writer.busy)
                    }

                    if receiver.receiving {
                        ProgressView(value: receiver.progress)
                    }

                    Divider()

                    // NFC Actions
                    HStack(spacing: 12) {
                        Button {
                            if let frame = receiver.frame {
                                receiver.stop()
                                writer.start(frame: frame)
                            }
                        } label: {
                            Label("更新電子紙", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(receiver.frame == nil || receiver.receiving || writer.busy)

                        Button {
                            receiver.stop()
                            writer.startAlignmentTest()
                        } label: {
                            Label("感應對位測試", systemImage: "wave.3.forward")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .disabled(receiver.receiving || writer.busy)
                    }

                    Text("提示：更新或對位測試時，請將 iPhone 頂端平貼電子紙背部天線微調。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("電子紙橋接")
    }
}
