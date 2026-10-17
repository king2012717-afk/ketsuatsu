import SwiftUI
import UIKit

extension View {
    /// この View が画面に入っている割合（0〜1）が変わったときに呼ぶ。画面から外れたら 0 を渡す。
    /// おすすめアプリの表示の計測に使う（仕様書 4-8：半分以上入ったときだけ送る）。
    func onVisibleFractionChange(_ action: @escaping (Double) -> Void) -> some View {
        modifier(VisibleFractionModifier(action: action))
    }
}

private struct VisibleFractionModifier: ViewModifier {
    let action: (Double) -> Void

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onChange(of: proxy.frame(in: .global), initial: true) { _, frame in
                            action(ImpressionTracker.visibleFraction(of: frame, in: Self.screenBounds))
                        }
                }
            }
            .onDisappear {
                action(0)
            }
    }

    /// 前面にある画面の大きさ（グローバル座標）。
    private static var screenBounds: CGRect {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.screen.bounds ?? .zero
    }
}
