// Stand-in for `xcrun coremlcompiler compile <model> <outdir>` on a machine
// without Xcode: Core ML's own runtime compiler does the same job.
import CoreML
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write(Data("usage: coremlc <model.mlpackage> <outdir>\n".utf8)); exit(64)
}
let source = URL(fileURLWithPath: args[1])
let outdir = URL(fileURLWithPath: args[2], isDirectory: true)
let target = outdir.appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".mlmodelc")
do {
    let compiled = try MLModel.compileModel(at: source)
    try? FileManager.default.removeItem(at: target)
    try FileManager.default.moveItem(at: compiled, to: target)
    print(target.path)
} catch {
    FileHandle.standardError.write(Data("coremlc: \(error)\n".utf8)); exit(1)
}
