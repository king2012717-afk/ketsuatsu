import Foundation

/// 同じ種類の処理を 1 つずつ順に実行し、待っている間にもっと新しい要求が来たら、古い要求は実行しない。
///
/// 「いまの状態に合わせて作り直す」処理に使う（通知の登録し直しなど）。要求のたびに別々に走らせると、
/// 先に始まった処理の後半が、あとから始まった処理の前半より後に動き、古い状態が残ることがある。
/// ここでは前の実行が終わるのを待ってから始め、最後の要求が必ず最後に、最新の状態で実行される。
@MainActor
final class LatestOnlyRunner {
    private var last: Task<Void, Never>?
    private var generation = 0

    /// 処理を予約する。前の実行が終わってから始まる。始まる時点でもっと新しい予約があれば、何もせずに終わる。
    /// - Returns: この予約の完了を待つための Task。
    @discardableResult
    func enqueue(_ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        generation += 1
        let mine = generation
        let previous = last
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, mine == self.generation else { return }
            await work()
        }
        last = task
        return task
    }

    /// 処理を予約し、終わるまで待つ。
    func run(_ work: @escaping @MainActor () async -> Void) async {
        await enqueue(work).value
    }
}
