import SwiftUI

enum DropZone {
    case left
    case center
    case right
    case none
}

struct DropIndicatorView: View {
    let zone: DropZone

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch zone {
                case .left:
                    HStack(spacing: 0) {
                        Color.accentColor.opacity(0.3)
                            .frame(width: 4)
                        Spacer()
                    }
                case .right:
                    HStack(spacing: 0) {
                        Spacer()
                        Color.accentColor.opacity(0.3)
                            .frame(width: 4)
                    }
                case .center:
                    Color.accentColor.opacity(0.1)
                case .none:
                    Color.clear
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .allowsHitTesting(false)
        }
    }

    static func zone(for location: CGPoint, in size: CGSize) -> DropZone {
        let fraction = location.x / size.width
        if fraction < 0.2 { return .left }
        if fraction > 0.8 { return .right }
        return .center
    }
}
