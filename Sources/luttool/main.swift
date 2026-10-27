import CameraCore
import Foundation

// luttool convert <in.cube|in.lut> <out.lut>
// luttool compose <target LUT> <LUT whose neutral curve is applied first> <out.lut>
// luttool curve <LUT>

func load(_ path: String) throws -> LUT3D {
    let url = URL(fileURLWithPath: path)
    return try LUT3D.parse(data: Data(contentsOf: url), fileExtension: url.pathExtension)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    switch arguments.first {
    case "convert" where arguments.count == 3:
        let lut = try load(arguments[1])
        try lut.binaryLUTData().write(to: URL(fileURLWithPath: arguments[2]))
        print("\(arguments[2]): \(lut.size)^3")
    case "compose" where arguments.count == 4:
        let target = try load(arguments[1])
        let curve = try load(arguments[2]).neutralCurve()
        let composed = try target.composing(preCurve: curve)
        try composed.binaryLUTData().write(to: URL(fileURLWithPath: arguments[3]))
        print("\(arguments[3]): \(composed.size)^3, curve of \(curve.count) points")
    case "curve" where arguments.count == 2:
        let curve = try load(arguments[1]).neutralCurve()
        print(curve.map { String(format: "%.3f", $0) }.joined(separator: " "))
    default:
        fail("usage: luttool convert <in> <out.lut> | compose <target> <curve source> <out.lut> | curve <lut>")
    }
} catch {
    fail("error: \(error)")
}
