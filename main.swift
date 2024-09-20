//
//  main.swift
//  DevourCMD
//
//  Created by Dan Scully on 4/4/24.
//

import Foundation
import Vision
import Cocoa
import AVFoundation

struct Cue {

    var time: CMTime
    var tag: String
}

var currCue : Cue = Cue(time: CMTime.invalid,tag: "")
var cues: [Cue] = []

func recognizeTextHandler(request: VNRequest, error: Error?, time: CMTime) {
    guard let observations =
            request.results as? [VNRecognizedTextObservation] else {
        return
    }
    let recognizedStrings = observations.compactMap { observation in
        // Return the string of the top VNRecognizedText instance.
        return observation.topCandidates(1).first?.string
    }
    
    let joined = recognizedStrings.joined()
    
    //let eosRegex = /.*(Cue.*) \d+\.?\d*s? \d+%.*/
    let eosRegex = /(Cue \d+(\.\d+)?) .*/
    guard let match = joined.firstMatch(of: eosRegex) else {return}
        
    // Process the recognized strings.
    let newCue = Cue(time: time, tag: String(match.1))
    if (currCue.tag != match.1){
        currCue = newCue
        cues.append(newCue)
        let cfStr:CFTypeRef = CMTimeCopyDescription(allocator:kCFAllocatorDefault, time:newCue.time)!
        let nsTypeString = cfStr as! NSString
        print("FOUND: " + newCue.tag + " at " + (nsTypeString as String))
    }
     //print(joined)
    
}



func main() async {
    print("Usage: path [x y h w skipframes]")
    print("Usage: path is the movie file to scan")
    print("Usage: (x, y, h, w) are normalized CGRect values to scan for text.  Origin is bottom left.  Smaller is better.  Defaults to full frame")
    print("Usage: skipframes is how many frames to skip in between scanning a frame.  Try 15 (which is the default")

    if (CommandLine.arguments.count < 2) {
        return
    }
    
    let path = CommandLine.arguments[1]
    var roiX =  0.0
    var roiY =  0.0
    var roiW =  1.0
    var roiH =  1.0
    var skipFrames = 15
    

    if (CommandLine.arguments.count > 5) {
        roiX = Double(CommandLine.arguments[2])!
        roiY = Double(CommandLine.arguments[3])!
        roiW = Double(CommandLine.arguments[4])!
        roiH = Double(CommandLine.arguments[5])!
    }
    
    if (CommandLine.arguments.count > 6) {
        skipFrames = Int(CommandLine.arguments[6])!
    }

    print("Scanning with settings:")
    print("file: " + path)
    print("search box: (" + String(roiX) + "," + String(roiY) + "," + String(roiW) + "," + String(roiH) + ")")
    print("skipframes: " + String(skipFrames))
    
    let asset = AVAsset(url: URL(fileURLWithPath: path))
    var assetReader:AVAssetReader
    
    assetReader = try! AVAssetReader(asset: asset)

    let tracks = try! await asset.loadTracks(withMediaType: AVMediaType.video)
    
    let videoOptions = [
               // kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                kCVPixelBufferWidthKey as String: 1920,
                kCVPixelBufferHeightKey as String: 1080,
    ]
    let output = AVAssetReaderTrackOutput(track: tracks[0], outputSettings: videoOptions)
    output.alwaysCopiesSampleData = false
    assetReader.add(output)
    assetReader.startReading()
    
    var buffer = output.copyNextSampleBuffer()
    let roi = CGRect(x: roiX, y: roiY, width: roiW, height: roiH)
    
    // iterate buffers
    while (buffer != nil) {
        guard let imageBuffer : CVPixelBuffer = CMSampleBufferGetImageBuffer(buffer!) else {return}

        let requestHandler = VNSequenceRequestHandler()
        
        let time = CMSampleBufferGetPresentationTimeStamp(buffer!)
        // Create a new request to recognize text.
        let compHandler = {(r:VNRequest,e:Error?) -> Void in
            return recognizeTextHandler(request: r, error: e, time: time)
        }
        
        let request = VNRecognizeTextRequest(completionHandler: compHandler)
        request.regionOfInterest = roi
        request.recognitionLevel = VNRequestTextRecognitionLevel.fast
        
        
        do {
            // Perform the text-recognition request.
            try requestHandler.perform([request], on: imageBuffer)
        } catch {
            print("Unable to perform the requests: \(error).")
        }
        buffer = output.copyNextSampleBuffer()
        
        //skip buffers
        var skip = skipFrames
        while ((buffer != nil) && (skip > 0))
        {
            buffer = output.copyNextSampleBuffer()
            skip = skip - 1
        }

    }
    await cues
    print("Completed Scanning for Cues")
    
    var chapters:[Chapter] = []
    
    for cue in await cues
    {
        let chapter = Chapter(time: cue.time, title: cue.tag)
        chapters.append(chapter)
    }
    
    let existingPath = URL(fileURLWithPath: path)
    let existingDirectory = existingPath.deletingLastPathComponent()
    var fileName = existingPath.lastPathComponent
    let fileExtension = fileName.split(separator: ".").last!
    fileName += "_chapters"
    let newPath = existingDirectory.appendingPathComponent(fileName).appendingPathExtension(String(fileExtension))
    print("Writine chapters into \(newPath).  This could take a while...")
    let exporter = VideoExporter(assetURL: URL(fileURLWithPath: path), chapters: chapters)
    await exporter.export(to: newPath)
    print("Completed Export")
}

await main()
