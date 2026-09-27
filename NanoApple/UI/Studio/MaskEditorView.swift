import AppKit
import SwiftUI

struct MaskEditorView: View {
    private struct Stroke: Identifiable {
        let id = UUID()
        var points: [CGPoint]
        let width: CGFloat
        let erases: Bool
    }

    @Environment(\.dismiss) private var dismiss

    let sourceURL: URL
    let onApply: (URL) -> Void

    @State private var strokes: [Stroke] = []
    @State private var activeStrokeID: UUID?
    @State private var brushWidth = 0.06
    @State private var erases = false
    @State private var errorMessage: String?

    private var sourceImage: NSImage {
        NSImage(contentsOf: sourceURL) ?? NSImage()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(L10n.Mask.title).font(.title2.bold())
                Spacer()
                Toggle(L10n.Mask.erase, isOn: $erases)
                    .toggleStyle(.button)
                Button(L10n.Mask.undo, systemImage: "arrow.uturn.backward") {
                    _ = strokes.popLast()
                }
                .disabled(strokes.isEmpty)
                Button(L10n.Mask.clear, systemImage: "trash") {
                    strokes.removeAll()
                }
                .disabled(strokes.isEmpty)
            }
            .padding()

            Divider()

            GeometryReader { geometry in
                let rect = aspectFitRect(imageSize: sourceImage.size, container: geometry.size)
                ZStack {
                    Color.black.opacity(0.08)
                    Image(nsImage: sourceImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Canvas { context, _ in
                        context.clip(to: Path(rect))
                        for stroke in strokes {
                            draw(stroke, in: rect, context: &context)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(maskGesture(in: rect))
                }
            }
            .frame(minHeight: 480)

            Divider()

            HStack(spacing: 12) {
                Text(L10n.Mask.brush)
                Slider(value: $brushWidth, in: 0.01...0.20)
                    .frame(width: 220)
                Circle()
                    .fill(erases ? Color.secondary : Color.red.opacity(0.65))
                    .frame(width: max(8, brushWidth * 90), height: max(8, brushWidth * 90))
                Text(L10n.Mask.hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.Characters.cancel) { dismiss() }
                Button(L10n.Mask.apply, systemImage: "checkmark") { applyMask() }
                    .buttonStyle(.borderedProminent)
                    .disabled(strokes.isEmpty)
            }
            .padding()
        }
        .frame(minWidth: 820, minHeight: 650)
        .alert(L10n.Mask.error, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func maskGesture(in rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard rect.contains(value.location), rect.width > 0, rect.height > 0 else { return }
                let point = CGPoint(
                    x: (value.location.x - rect.minX) / rect.width,
                    y: (value.location.y - rect.minY) / rect.height
                )
                if let id = activeStrokeID,
                   let index = strokes.firstIndex(where: { $0.id == id }) {
                    strokes[index].points.append(point)
                } else {
                    let stroke = Stroke(points: [point], width: brushWidth, erases: erases)
                    strokes.append(stroke)
                    activeStrokeID = stroke.id
                }
            }
            .onEnded { _ in activeStrokeID = nil }
    }

    private func draw(_ stroke: Stroke, in rect: CGRect, context: inout GraphicsContext) {
        guard let first = stroke.points.first else { return }
        var path = Path()
        path.move(to: point(first, in: rect))
        if stroke.points.count == 1 {
            path.addLine(to: point(first, in: rect))
        } else {
            for value in stroke.points.dropFirst() {
                path.addLine(to: point(value, in: rect))
            }
        }
        context.blendMode = stroke.erases ? .destinationOut : .normal
        context.stroke(
            path,
            with: .color(.red.opacity(0.55)),
            style: StrokeStyle(
                lineWidth: stroke.width * min(rect.width, rect.height),
                lineCap: .round,
                lineJoin: .round
            )
        )
        context.blendMode = .normal
    }

    private func point(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }

    private func aspectFitRect(imageSize: CGSize, container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func applyMask() {
        do {
            let representations = sourceImage.representations
            let width = representations.map(\.pixelsWide).max() ?? Int(sourceImage.size.width)
            let height = representations.map(\.pixelsHigh).max() ?? Int(sourceImage.size.height)
            guard width > 0, height > 0,
                  let bitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: width,
                    pixelsHigh: height,
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                  ) else {
                throw CocoaError(.fileWriteUnknown)
            }

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            for stroke in strokes {
                drawBitmapStroke(stroke, width: width, height: height)
            }
            NSGraphicsContext.restoreGraphicsState()

            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "NanoAppleMasks", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appending(path: "mask-\(UUID().uuidString).png")
            try data.write(to: destination, options: .atomic)
            onApply(destination)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func drawBitmapStroke(_ stroke: Stroke, width: Int, height: Int) {
        guard let first = stroke.points.first else { return }
        let path = NSBezierPath()
        path.lineWidth = stroke.width * CGFloat(min(width, height))
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: first.x * CGFloat(width), y: (1 - first.y) * CGFloat(height)))
        for point in stroke.points.dropFirst() {
            path.line(to: NSPoint(x: point.x * CGFloat(width), y: (1 - point.y) * CGFloat(height)))
        }
        (stroke.erases ? NSColor.black : NSColor.white).setStroke()
        path.stroke()
        if stroke.points.count == 1 {
            let radius = path.lineWidth / 2
            let center = NSPoint(x: first.x * CGFloat(width), y: (1 - first.y) * CGFloat(height))
            let dot = NSBezierPath(ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
            (stroke.erases ? NSColor.black : NSColor.white).setFill()
            dot.fill()
        }
    }
}
