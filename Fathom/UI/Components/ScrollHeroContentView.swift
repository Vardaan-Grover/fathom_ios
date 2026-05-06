import SwiftUI

struct ScrollHeroContentView: View {
    @State private var config: ScrollHeroEffectConfig = .init()
    @State private var config1: ScrollHeroEffectConfig = .init()
    @Namespace private var namespace
    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    Section("Sceneric") {
                        SourceHeroEffectScrollView(
                            config: $config, namespace: namespace, data: sceneric, id: \.id
                        ) { item in
                            ImageView(item)
                                .onTapGesture {
                                    if let index = sceneric.firstIndex(where: { $0.id == item.id })
                                    {
                                        withAnimation(.interpolatingSpring(duration: 0.5)) {
                                            config.sourceIndex = index
                                            config.expandDetailView = true
                                        }
                                    }
                                }
                                .transition(.offset(x: 1))
                        }
                        .frame(height: 220)
                    }

                    Section("Illustrations") {
                        SourceHeroEffectScrollView(
                            config: $config1, namespace: namespace, data: illustrations, id: \.id
                        ) { item in
                            ImageView(item)
                                .onTapGesture {
                                    if let index = illustrations.firstIndex(where: {
                                        $0.id == item.id
                                    }) {
                                        withAnimation(.interpolatingSpring(duration: 0.5)) {
                                            config1.sourceIndex = index
                                            config1.expandDetailView = true
                                        }
                                    }
                                }
                                .transition(.offset(x: 1))
                        }
                        .frame(height: 220)
                    }
                }
            }
            .safeAreaPadding(.horizontal, 15)

        }
        .overlay {
            // Place your Detail View at the highest possible order!
            ZStack {
                DetailHeroEffectScrollView(
                    config: $config, namespace: namespace, data: sceneric, id: \.id
                ) { item, progress in
                    DetailItemView(
                        config: $config, photo: item, progress: progress, namespace: namespace)
                }

                DetailHeroEffectScrollView(
                    config: $config1, namespace: namespace, data: illustrations, id: \.id
                ) { item, progress in
                    DetailItemView(
                        config: $config1, photo: item, progress: progress, namespace: namespace)
                }
            }
            .safeAreaPadding(.horizontal, 20)
        }
    }

    /// Image View
    @ViewBuilder
    func ImageView(_ item: Photo) -> some View {
        Rectangle()
            .foregroundStyle(.clear)
            .overlay {
                Image(item.assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipShape(.rect(cornerRadius: 10))
            .matchedGeometryEffect(id: item.imageID, in: namespace)
    }
}

struct DetailItemView: View {
    @Binding var config: ScrollHeroEffectConfig
    var photo: Photo
    var progress: CGFloat
    var namespace: Namespace.ID

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack {
                Image(photo.assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 160, height: 220)
                    .clipShape(.rect(cornerRadius: 20))
                    .matchedGeometryEffect(id: photo.imageID, in: namespace)

                VStack(spacing: 12) {
                    Text(photo.author)
                        .font(.title2.bold())

                    Text("lorem ipsum")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .kerning(0.5)
                }
                .compositingGroup()
                .opacity(opacity)
            }
            .padding(15)
        }
        .safeAreaInset(edge: .bottom) {
            BottomBar()
                .opacity(opacity)
        }
        .overlay(alignment: .topTrailing) {
            /// Close Button
            Button {
                withAnimation(.interpolatingSpring(duration: 0.5)) {
                    config.expandDetailView = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .padding(15)
                    .contentShape(.rect)
            }
            .opacity(opacity)
        }
    }

    /// Custom Buttom bar
    @ViewBuilder
    func BottomBar() -> some View {
        HStack(spacing: 10) {
            Button {

            } label: {
                Text("Add to Favorite ")
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)

            }
            .tint(.red)

            Button {

            } label: {
                Text("Download")
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)

            }
            .tint(.blue)
        }
        .font(.callout)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    /// Let's Convert the progress to opacity to only show after specific limit
    var opacity: CGFloat {
        return progress > 0.7 ? min((progress - 0.7) * 3.4, 1) : 0
    }
}
