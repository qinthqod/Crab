import AppKit
import SwiftUI

enum CrabLoadingMotion {
    case scuttle
    case pinch
}

/// Crab's shared indeterminate activity indicator.
///
/// It only animates transforms, so loading feedback does not trigger layout work.
/// When Reduce Motion is enabled, the mascot remains still and the status text
/// continues to communicate progress.
struct CrabLoadingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let size: CGFloat
    var motion: CrabLoadingMotion = .scuttle

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let phase = seconds * 2 * Double.pi / cycleDuration
            let travel = reduceMotion ? 0 : sin(phase)
            let step = reduceMotion ? 0 : sin(phase * 2)
            let pinch = reduceMotion ? 0 : (0.5 + 0.5 * sin(phase * 2.15))

            CrabMascotArtwork(clawAngle: pinch * 7)
                .frame(width: size, height: size)
                .scaleEffect(
                    x: reduceMotion ? 1 : 1 + abs(step) * 0.018,
                    y: reduceMotion ? 1 : 1 - abs(step) * 0.012
                )
                .rotationEffect(.degrees(rotation(for: travel, step: step)))
                .offset(
                    x: horizontalOffset(for: travel),
                    y: reduceMotion ? 0 : -abs(step) * size * 0.025
                )
                .shadow(color: Color.crabPurple.opacity(0.13), radius: size * 0.09, y: size * 0.06)
        }
        .frame(width: size * 1.42, height: size)
        .accessibilityHidden(true)
    }

    private var cycleDuration: Double {
        switch motion {
        case .scuttle: 1.55
        case .pinch: 1.15
        }
    }

    private func horizontalOffset(for travel: Double) -> CGFloat {
        guard motion == .scuttle else { return 0 }
        return travel * size * 0.18
    }

    private func rotation(for travel: Double, step: Double) -> Double {
        switch motion {
        case .scuttle: travel * 2.2
        case .pinch: step * 1.4
        }
    }
}

private struct CrabMascotArtwork: View {
    let clawAngle: Double

    var body: some View {
        ZStack {
            mascot
                .mask(CrabBodyMask())

            mascot
                .mask(CrabLeftClawMask())
                .rotationEffect(.degrees(-clawAngle), anchor: UnitPoint(x: 0.35, y: 0.55))

            mascot
                .mask(CrabRightClawMask())
                .rotationEffect(.degrees(clawAngle), anchor: UnitPoint(x: 0.69, y: 0.59))
        }
    }

    private var mascot: some View {
        Group {
            if let image = CrabMascotImage.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.crabPurple)
                    .padding(24)
            }
        }
    }
}

private enum CrabMascotImage {
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "crab-loading-mascot", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}

private struct CrabBodyMask: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let size = proxy.size
                path.addRoundedRect(
                    in: CGRect(x: size.width * 0.23, y: size.height * 0.35, width: size.width * 0.56, height: size.height * 0.43),
                    cornerSize: CGSize(width: size.width * 0.16, height: size.height * 0.16)
                )
                path.addRect(CGRect(x: size.width * 0.16, y: size.height * 0.54, width: size.width * 0.70, height: size.height * 0.28))
            }
            .fill(.white)
        }
    }
}

private struct CrabLeftClawMask: View {
    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .frame(width: proxy.size.width * 0.34, height: proxy.size.height * 0.43)
                .position(x: proxy.size.width * 0.30, y: proxy.size.height * 0.39)
        }
    }
}

private struct CrabRightClawMask: View {
    var body: some View {
        GeometryReader { proxy in
            Rectangle()
                .frame(width: proxy.size.width * 0.31, height: proxy.size.height * 0.43)
                .position(x: proxy.size.width * 0.75, y: proxy.size.height * 0.45)
        }
    }
}
