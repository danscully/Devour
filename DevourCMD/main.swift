//
//  main.swift
//  DevourCMD
//
//  Created by Dan Scully on 9/27/24.
//

import Foundation
import Vision


func main() async {
    print("Usage: path [x y w h]")
    print("Usage: path is the movie file to scan")
    print("Usage: (x, y, w, h) Size (in pixels) of the Region of Interest containing the Cue text to recognize.  Origin is top left.")
    
    if (CommandLine.arguments.count < 2) {
        return
    }
    
    let path = CommandLine.arguments[1]
    var roiX =  0
    var roiY =  0
    var roiW =  0
    var roiH =  0
    
    if (CommandLine.arguments.count > 5) {
        roiX = Int(CommandLine.arguments[2])!
        roiY = Int(CommandLine.arguments[3])!
        roiW = Int(CommandLine.arguments[4])!
        roiH = Int(CommandLine.arguments[5])!
    }
    
    let url = URL(fileURLWithPath: path)
    var frameProvider: FrameProvider
    
    do {
        frameProvider = try await FrameProvider(URL: url)
    } catch {
        print("Encounterd an error while opening movie asset. \(error)")
        return
    }
    let size = frameProvider.size
    
    if roiW == 0 || roiH == 0 {
        roiW = Int(size.width)
        roiH = Int(size.height)
        
    }
    
    let adjustedRoiX:CGFloat = CGFloat(roiX)/size.width
    let adjustedRoiY:CGFloat = (size.height - CGFloat(roiY+roiH))/size.height
    let adjustedRoiW:CGFloat = CGFloat(roiW)/size.width
    let adjustedRoiH:CGFloat = CGFloat(roiH)/size.height

    
    let roi = NormalizedRect(x: adjustedRoiX, y: adjustedRoiY, width: adjustedRoiW, height: adjustedRoiH)

    let existingPath = URL(fileURLWithPath: path)
    let existingDirectory = existingPath.deletingLastPathComponent()
    var fileName = existingPath.lastPathComponent
    var filenamePieces = fileName.split(separator: ".")
    var newName = ""
    
    if filenamePieces.count > 1 {
        let ext = filenamePieces.removeLast()
        let base = filenamePieces.joined(separator: ".")
        newName = base + "_devoured." + String(ext)
    }   else {
        newName = fileName + "_devoured"
    }
    
    let newPath = existingDirectory.appendingPathComponent(newName)
    print("Output being written to: \(newPath).")
    
    print("Beginning Scanning and Encoding...")
    print("")
    let dv = Devourer(roi: roi, url: url, outputUrl: newPath) {progress in
        print("\u{1B}[1A\u{1B}[K\(progress)")
    }
    do {
        try await dv.execute()
        print("Scanning and Encoding Complete.")
    } catch {
        print("Encounterd an error while processing. \(error)")
    }
}

await main()
