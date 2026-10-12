import AppKit
import SwiftUI

struct IconAnimatedCenterPreview: View {
    let scene: IconSceneState
    let size: CGFloat
    let appearance: NSAppearance?
    let centerIdentity: IconPreviewCenterIdentity
    var chargingPhase: ChargingEffectPhase? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var driver = IconPreviewTransitionDriver()


    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !driver.transition.isActive(at: Date()))) { timeline in
            let progress = driver.transition.progress(at: timeline.date)
            ZStack {
                rendered(IconSceneState(outerRing: scene.outerRing), phase: chargingPhase)
                if let center = scene.center {
                    rendered(IconSceneState(center: center))
                        .opacity(driver.transition.outgoingCenter == nil ? 1 : progress)
                        .offset(x: driver.transition.usesReduceMotion ? 0 : 12 * (1 - progress))
                }
                if let outgoingCenter = driver.transition.outgoingCenter {
                    rendered(IconSceneState(center: outgoingCenter))
                        .opacity(1 - progress)
                        .offset(x: driver.transition.usesReduceMotion ? 0 : -12 * progress)
                        .accessibilityHidden(true)
                }
                rendered(IconSceneState(footer: scene.footer))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            driver.setInitial(center: scene.center, identity: centerIdentity)
        }
        .onChange(of: PreviewTransitionInput(center: scene.center, identity: centerIdentity)) { input in
            driver.update(center: input.center, identity: input.identity,
                          reduceMotion: reduceMotion, now: Date())
        }
        .onChange(of: reduceMotion) { isReduced in
            driver.setReduceMotion(isReduced, now: Date())
        }
        .task(id: driver.transition.generation) {
            let generation = driver.transition.generation
            guard driver.transition.outgoingCenter != nil else { return }
            do {
                try await Task.sleep(for: .seconds(driver.transition.activeDuration))
                guard !Task.isCancelled else { return }
                driver.clear(generation: generation)
            } catch {
                // Cancellation on a newer center state or when the view disappears is expected.
            }
        }
        .onDisappear {
            driver.reset()
        }
    }

    private func rendered(
        _ scene: IconSceneState,
        phase: ChargingEffectPhase? = nil
    ) -> some View {
        Image(nsImage: StatusIconRenderer.image(
            scene: scene,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            appearance: appearance,
            phase: phase
        ) ?? NSImage(size: NSSize(width: size, height: size)))
        .resizable()
        .interpolation(.high)
        .frame(width: size, height: size)
    }
}

private struct PreviewTransitionInput: Equatable {
    let center: CenterState?
    let identity: IconPreviewCenterIdentity
}
