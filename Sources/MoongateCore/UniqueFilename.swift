import Foundation

/// 产物文件命名去重：在目标目录里为一个 `stem.ext` 选出不与现有文件冲突的 URL。
///
/// 首选 `stem.ext`；若已存在，则依次尝试 `stem<sep>2.ext`、`stem<sep>3.ext`… 直到找到空位。
/// 这是「同一视频多次下载 / 重复导入字幕 / 重跑云端 ASR」时避免覆盖已有产物的统一实现——
/// 此前 QueueManager（导入字幕）、CloudASR（云端 ASR sidecar）、SettingsView（导入模型）
/// 各写了一份等价的 `-<n>` 循环，Burner 写了一份 ` <n>`（空格）循环，四处均无测试。
/// 收敛到这里做单一可测来源；`separator` 参数保留各调用点的既有命名（默认 `-`，Burner 传 " "）。
///
/// 判存回调 `fileExists` 默认走 `FileManager`，测试可注入以避免真实文件系统。
public enum UniqueFilename {

    /// 为 `stem` + `ext` 在 `directory` 里选出不冲突的文件 URL。
    /// - Parameters:
    ///   - directory: 目标目录。
    ///   - stem: 不含扩展名的文件主名（调用方负责清洗非法字符）。
    ///   - ext: 扩展名，不含点；空串表示无扩展名。
    ///   - separator: 序号分隔符，默认 `-`；Burner 用 " " 以保留「<原名>（字幕版） 2.mp4」的既有观感。
    ///   - fileExists: 判断某路径是否已被占用（默认查 FileManager）。
    public static func url(
        in directory: URL,
        stem: String,
        ext: String,
        separator: String = "-",
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        var candidate = compose(directory: directory, stem: stem, ext: ext)
        var index = 2
        while fileExists(candidate.path) {
            candidate = compose(directory: directory, stem: "\(stem)\(separator)\(index)", ext: ext)
            index += 1
        }
        return candidate
    }

    /// 拼 `directory/stem(.ext)`。ext 为空时不加点。
    private static func compose(directory: URL, stem: String, ext: String) -> URL {
        let base = directory.appendingPathComponent(stem, isDirectory: false)
        return ext.isEmpty ? base : base.appendingPathExtension(ext)
    }
}
