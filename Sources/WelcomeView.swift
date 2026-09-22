import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var session: GroveSession
    @Environment(\.colorScheme) private var scheme

    private var places: [(String, String, String)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            ("house.fill", Copy.home, home.path),
            ("arrow.down.circle.fill", FileManager.default.displayName(atPath: home.appendingPathComponent("Downloads").path), home.appendingPathComponent("Downloads").path),
            ("doc.fill", FileManager.default.displayName(atPath: home.appendingPathComponent("Documents").path), home.appendingPathComponent("Documents").path),
            ("menubar.dock.rectangle", FileManager.default.displayName(atPath: home.appendingPathComponent("Desktop").path), home.appendingPathComponent("Desktop").path),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                placeGrid
                if session.rootPath != nil {
                    Button(action: session.returnToMap) {
                        Label(Copy.continueMap, systemImage: "map")
                    }
                    .buttonStyle(.bordered)
                }
                diskSection
                recentSection
            }
            .padding(36)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(GroveColor.canvas(scheme))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 22) {
            treemapMark
            VStack(alignment: .leading, spacing: 6) {
                Text("Grove")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                Text(Copy.tagline)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var treemapMark: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(GroveColor.folder(name: "home", scheme: scheme))
                .frame(width: 78, height: 92)
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(FileCategory.video.color(in: scheme))
                    .frame(width: 58, height: 44)
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(FileCategory.image.color(in: scheme))
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(FileCategory.archive.color(in: scheme))
                }
                .frame(width: 58, height: 43)
            }
        }
        .padding(10)
        .background(.black.opacity(scheme == .dark ? 0.2 : 0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var placeGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(places, id: \.2) { place in
                    placeButton(symbol: place.0, title: place.1, path: place.2)
                }
            }
            Button(action: session.chooseFolder) {
                Label(Copy.chooseFolder, systemImage: "folder.badge.plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func placeButton(symbol: String, title: String, path: String) -> some View {
        Button {
            session.start(URL(fileURLWithPath: path))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(red: 0.20, green: 0.48, blue: 0.36))
                    .frame(width: 22)
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.background.opacity(scheme == .dark ? 0.45 : 0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var diskSection: some View {
        let disks = GroveSession.volumes()
        return VStack(alignment: .leading, spacing: 8) {
            Text(Copy.disks)
                .font(.headline)
            ForEach(disks) { disk in
                Button {
                    session.start(URL(fileURLWithPath: disk.path))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "internaldrive")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(disk.name)
                            if disk.total > 0 {
                                capacity(disk.free, total: disk.total)
                            }
                        }
                        Spacer()
                        if disk.total > 0 {
                            Text("\(Format.bytes(disk.free)) \(Copy.free)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recentSection: some View {
        let paths = GroveSession.recentPaths()
        return Group {
            if !paths.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Copy.recents)
                        .font(.headline)
                    ForEach(paths, id: \.self) { path in
                        Button {
                            session.start(URL(fileURLWithPath: path))
                        } label: {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                                Text(path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func capacity(_ free: Int64, total: Int64) -> some View {
        GeometryReader { proxy in
            let used = total > 0 ? CGFloat(total - free) / CGFloat(total) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(Color(red: 0.20, green: 0.48, blue: 0.36))
                    .frame(width: max(4, proxy.size.width * min(max(used, 0), 1)))
            }
        }
        .frame(height: 5)
        .frame(maxWidth: 180)
    }
}
