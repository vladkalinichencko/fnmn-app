import CreateML
import Foundation

// Trains the digest's topic classifier: every row is one text and the folder it belongs to.
//     swift server/digest/classifier/Train.swift rows.json classifier.mlmodel

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: Train.swift rows.json out.mlmodel\n".utf8))
    exit(2)
}
let rows = try MLDataTable(contentsOf: URL(fileURLWithPath: arguments[1]))
let classifier = try MLTextClassifier(trainingData: rows, textColumn: "text", labelColumn: "label")
try classifier.write(to: URL(fileURLWithPath: arguments[2]))
print("trained on \(rows.rows.count) rows")
