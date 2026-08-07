import SwiftUI

/// 新規記録の入り口。ホームと履歴の両方から同じ流れを呼べるようにまとめている。
enum AddRecordRoute: Identifiable, Hashable {
    case manual
    case camera
    case photoLibrary

    var id: Self { self }
}

struct AddRecordFlowModifier: ViewModifier {
    @Binding var route: AddRecordRoute?
    var defaultArm: MeasurementArm

    func body(content: Content) -> some View {
        content.sheet(item: $route) { route in
            switch route {
            case .manual:
                RecordEditView(mode: .create(BPDraft(arm: defaultArm)))
            case .camera:
                CaptureFlowView(source: .camera)
            case .photoLibrary:
                CaptureFlowView(source: .photoLibrary)
            }
        }
    }
}

extension View {
    func addRecordFlow(route: Binding<AddRecordRoute?>, defaultArm: MeasurementArm) -> some View {
        modifier(AddRecordFlowModifier(route: route, defaultArm: defaultArm))
    }
}

/// 「＋」ボタン用のメニュー。カメラが使えない端末では撮影を出さない。
struct AddRecordMenu<LabelContent: View>: View {
    @Binding var route: AddRecordRoute?
    @ViewBuilder var label: () -> LabelContent

    var body: some View {
        Menu {
            if CameraPicker.isAvailable {
                Button {
                    route = .camera
                } label: {
                    Label("血圧計を撮影して記録", systemImage: "camera.fill")
                }
            }
            Button {
                route = .photoLibrary
            } label: {
                Label("写真から読み取る", systemImage: "photo.on.rectangle")
            }
            Button {
                route = .manual
            } label: {
                Label("手で入力する", systemImage: "square.and.pencil")
            }
        } label: {
            label()
        }
    }
}
