import SwiftUI

/// Model choice + download/status, shared by Settings and the setup guide.
struct SmartFillControls: View {
    @Bindable var smart = SmartFill.shared
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(SmartFill.models) { model in
                ModelRow(model: model, selected: smart.selectedModelID == model.id, downloaded: smart.isDownloaded(model)) {
                    smart.selectedModelID = model.id
                }
            }
            status
        }
    }

    @ViewBuilder private var status: some View {
        HStack(spacing: 10) {
            switch smart.state {
            case .off:
                Text("Smart Fill is off — Tab uses the built-in pattern engine.")
                    .font(.system(size: 12)).foregroundStyle(Color.haloSecondary)
                Spacer()
                Button("Turn On") { smart.enabled = true }.buttonStyle(.glass).controlSize(.small)
            case .notDownloaded:
                Text("One-time download, \(ByteCountFormatter.string(fromByteCount: smart.model.bytes, countStyle: .file)). Runs offline on this Mac.")
                    .font(.system(size: 12)).foregroundStyle(Color.haloSecondary)
                Spacer()
                Button("Download") { smart.downloadModel() }
                    .buttonStyle(.glassProminent).tint(Color.haloAction).controlSize(.small)
            case .downloading(let progress):
                ProgressView(value: progress).frame(maxWidth: .infinity)
                Text("\(Int(progress * 100))%").font(.system(size: 12).monospacedDigit()).foregroundStyle(Color.haloSecondary)
                Button("Cancel") { smart.cancelDownload() }.buttonStyle(.glass).controlSize(.small)
            case .starting:
                ProgressView().controlSize(.small)
                Text("Loading the model…").font(.system(size: 12)).foregroundStyle(Color.haloSecondary)
                Spacer()
            case .ready:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.haloAdded)
                Text(smart.lastLatency.map { "Ready — last suggestion in \($0) ms" } ?? "Ready — running on this Mac")
                    .font(.system(size: 12)).foregroundStyle(Color.haloSecondary)
                Spacer()
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(nsColor: Palette.warning))
                Text(message).font(.system(size: 12)).foregroundStyle(Color.haloSecondary).lineLimit(2)
                Spacer()
                Button("Retry") { smart.refresh(); if case .notDownloaded = smart.state { smart.downloadModel() } }
                    .buttonStyle(.glass).controlSize(.small)
            }
        }
        .frame(minHeight: 26)
    }
}

private struct ModelRow: View {
    let model: SmartFill.Model
    let selected: Bool
    let downloaded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Color.haloAction : Color.haloTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(model.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.haloText)
                        Text(ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file))
                            .font(.system(size: 11)).foregroundStyle(Color.haloTertiary)
                        if downloaded {
                            Text("Downloaded").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Color.haloAdded)
                        }
                    }
                    Text(model.detail).font(.system(size: 11.5)).foregroundStyle(Color.haloSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? Color.haloSky.opacity(0.08) : Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? Color.haloSky.opacity(0.35) : Color.haloHairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Status-bar hint while the model downloads or once it's working.
struct SmartFillBadge: View {
    let smart = SmartFill.shared

    var body: some View {
        switch smart.state {
        case .downloading(let progress):
            Label("Model \(Int(progress * 100))%", systemImage: "arrow.down.circle")
        case .starting:
            Label("Loading model", systemImage: "hourglass")
        case .ready:
            Label("Smart Fill", systemImage: "cpu")
                .help("Tab suggestions from a local model running on this Mac")
        default:
            EmptyView()
        }
    }
}
