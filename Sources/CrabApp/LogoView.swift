import AppKit
import SwiftUI

struct LogoView: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.crabPurple)
                    .padding(size * 0.18)
                    .background(Color.crabLavender, in: Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Crab 保护环")
    }

    private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "crab-protective-orbit", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}
