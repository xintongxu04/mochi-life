import SwiftUI
import UIKit

/// A food's product photo, bundled with the app so it works offline, or a placeholder icon
/// for foods without one.
struct FoodThumbnail: View {
    let food: Food
    let size: CGFloat

    var body: some View {
        Group {
            if let image = FoodThumbnails.image(for: food) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .background(.white)
            } else {
                Image(systemName: "fork.knife")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.fill.tertiary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.18))
        .accessibilityHidden(true)
    }
}

/// Looks up bundled product photos. Photos are listed in a small file that maps each library
/// food to its picture, so a food keeps its photo even if it's renamed.
enum FoodThumbnails {
    private static let bundledLists = ["tiki-cat-thumbnails"]

    private static let fileNames: [String: String] = {
        var names: [String: String] = [:]
        for list in bundledLists {
            guard let url = Bundle.main.url(forResource: list, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let entries = try? JSONDecoder().decode([String: String].self, from: data)
            else { continue }
            names.merge(entries) { current, _ in current }
        }
        return names
    }()

    static func image(for food: Food) -> UIImage? {
        guard let identifier = food.libraryIdentifier,
              let fileName = fileNames[identifier]
        else { return nil }
        return UIImage(named: fileName)
    }
}
