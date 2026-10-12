import SwiftUI

/// The guide in a sheet: a search field over the topics, each with its steps (`HelpGuide`).
struct HelpView: View {
    var onClose: () -> Void
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("How to Use Hestia")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { onClose() }
            }
            TextField("Search the guide, for example: zoom, walk, exact wall", text: $search)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let found = HelpGuide.search(search)
                    if found.isEmpty {
                        Text("Nothing in the guide matches \u{201C}\(search)\u{201D}.")
                            .foregroundColor(.secondary)
                    }
                    ForEach(found) { topic in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(topic.title)
                                .font(.headline)
                            ForEach(topic.lines, id: \.self) { line in
                                Text("\u{2022} " + line)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 600, height: 640)
    }
}
