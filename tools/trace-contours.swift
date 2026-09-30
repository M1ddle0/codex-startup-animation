import Foundation
import Vision

// Offline vectorization: shipping paths avoids image processing during startup.
let request = VNDetectContoursRequest()
request.contrastAdjustment = 1.4
request.detectsDarkOnLight = true
request.maximumImageDimension = 1200
try VNImageRequestHandler(url: URL(fileURLWithPath: CommandLine.arguments[1])).perform([request])
guard let observation = request.results?.first else { fatalError("No contours") }
var paths = [[[Double]]]()
for index in 0..<observation.contourCount {
    let contour = try observation.contour(at: index)
    let polygon = try contour.polygonApproximation(epsilon: 0.00065)
    let points = polygon.normalizedPoints.map { [Double(($0.x * 1536).rounded()), Double(((1 - $0.y) * 1024).rounded())] }
    guard points.count >= 5 else { continue }
    let length = zip(points, points.dropFirst()).reduce(0.0) { $0 + hypot($1.0[0] - $1.1[0], $1.0[1] - $1.1[1]) }
    if length > 20 { paths.append(points + [points[0]]) }
}
let data = try JSONSerialization.data(withJSONObject: paths)
let js = "window.CONTOUR_PATHS=" + String(data: data, encoding: .utf8)! + ";\n"
try js.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
print("Vectorized \(paths.count) paths, \(data.count) bytes")
