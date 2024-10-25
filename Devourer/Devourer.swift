//
//  devourer.swift
//  DevourCMD
//
//  Created by Dan Scully on 4/4/24.
//

import Foundation
import Vision
import Cocoa
import AVFoundation

actor FrameProvider {
    
    let size:CGSize
    let url:URL
    let asset:AVAsset
    let assetReader:AVAssetReader
    let output:AVAssetReaderTrackOutput
    let nomFPS:Float
    let length:CMTime
    let lengthInFrames:Int64
    let duration:CMTime = CMTime(value:10,timescale:600)
    let cursor:AVSampleCursor
    var lastIndex:Int64 = 0
    
    
    init(URL:URL) async throws {
        self.url = URL
        self.asset = AVAsset(url: URL)
       
        self.assetReader = try AVAssetReader(asset: asset)
        
        let tracks = try await asset.loadTracks(withMediaType: AVMediaType.video)
        self.size = tracks[0].naturalSize.applying(tracks[0].preferredTransform)
        self.nomFPS = tracks[0].nominalFrameRate
        self.cursor = tracks[0].makeSampleCursor(presentationTimeStamp: .zero)!
        self.length = tracks[0].timeRange.duration
        self.lengthInFrames = Int64(CMTimeGetSeconds(length) * Double(nomFPS))
        print("MinFrameDuration: \(tracks[0].minFrameDuration)")
        let videoOptions = [
            // kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
        ]
        
        self.output = AVAssetReaderTrackOutput(track: tracks[0], outputSettings: videoOptions)
        output.alwaysCopiesSampleData = false
        output.supportsRandomAccess = true
        assetReader.add(output)
    }
    
    func clone() async throws -> FrameProvider {
        return try await FrameProvider(URL: self.url)
    }
    
    func getFrame(index:Int64) async throws -> CMSampleBuffer? {
        if (Float64(index) / Float64(self.nomFPS)) > CMTimeGetSeconds(self.length) {
            print ("FATALish ERROR: Index \(index) is out of bounds")
            return nil
        }
        
        let change = self.cursor.stepInPresentationOrder(byCount: index - self.lastIndex)
        self.lastIndex += change
        let timeRange = CMTimeRange(start: self.cursor.presentationTimeStamp, duration: self.duration)
        if (self.assetReader.status == .reading) {
            self.output.reset(forReadingTimeRanges: [NSValue(timeRange: timeRange)])
        } else {
            self.assetReader.timeRange = timeRange
            self.assetReader.startReading()
        }
        
        let sampleBuffer = output.copyNextSampleBuffer()
        while (output.copyNextSampleBuffer() != nil) {} //Eat any buffers left
        
        return sampleBuffer
    }
}

struct Cue {
    
    var time: CMTime
    var tag: String
    
    func printCue() {
        let cfStr:CFTypeRef = CMTimeCopyDescription(allocator:kCFAllocatorDefault, time:self.time)!
        let nsTypeString = cfStr as! NSString
        print("CUE: " + self.tag + " at " + (nsTypeString as String))
    }
}

struct Batch {
    var index:Int = 0
    var start:Int64 = 0
    var end:Int64 = 0
    var cues:[Cue] = []
    var frameProvider:FrameProvider?
}

class Devourer {
    var decodes:Int = 0
    var cuesFound:Int = 0
    let url:URL
    let outputUrl: URL
    let roi:NormalizedRect
    let skipFrames:Int64 = 1
    let progressMsg: (String) -> Void
    let batchCount:Int = 5
    var batches:[Batch] = []
    
    init(roi: NormalizedRect, url: URL, outputUrl: URL, progressMsg: @escaping (String) -> Void) {
        self.url = url
        self.roi = roi
        self.outputUrl = outputUrl
        self.progressMsg = progressMsg
    }
    
    func incrementCuesFound() {
        self.cuesFound += 1
        progressMsg("Decoded Frames: \(self.decodes), Cues Found: \(self.cuesFound)")
    }
    
    func incrementDecodes() {
        self.decodes += 1
        progressMsg("Decoded Frames: \(self.decodes), Cues Found: \(self.cuesFound)")
    }
    
    
    func getCueForBuffer(buffer: CMSampleBuffer) async throws -> Cue {
        incrementDecodes()
        var request = RecognizeTextRequest()
        request.regionOfInterest = self.roi
        request.recognitionLevel = RecognizeTextRequest.RecognitionLevel.fast
        
        let time = CMSampleBufferGetPresentationTimeStamp(buffer)
        let pxBuffer:CVPixelBuffer = CMSampleBufferGetImageBuffer(buffer)!
        
        let result = try await request.perform(on: pxBuffer)
        let recognizedStrings = result.compactMap { observation in
            return observation.topCandidates(1).first?.string
        }
        let joined = recognizedStrings.joined()
        // print("Joined text: " + joined)
        // Removed space from end of regex match
        let eosRegex = /((?:(?:Cue)|(?:CUE)) \d+(\.\d+)?).*/
        var cueLabel:String
        if let match = joined.firstMatch(of: eosRegex) {
            cueLabel = String(match.1)
        } else {
            cueLabel = ""
        }
        
        return Cue(time: time, tag: cueLabel)
        
    }
    
    func recursiveScan(frameProvider: FrameProvider, left: Int64,right: Int64, leftCue: Cue, rightCue: Cue, accuracy: Int64) async throws -> (l: Cue,r: Cue, uniqueCues: [Cue]){
        
        let mid = left + (right-left)/2
        let ctrLeftCue = try await getCueForBuffer(buffer: frameProvider.getFrame(index: mid)!)
        let ctrRightCue = try await getCueForBuffer(buffer: frameProvider.getFrame(index: mid+1)!)
        
        var valLL,valLR,valRL,valRR:Cue
        var cuesL,cuesR: [Cue]
        
        if (leftCue.tag == ctrLeftCue.tag) {
            valLL = leftCue
            valLR = leftCue
            cuesL = []
        } else if ((left + accuracy) >= mid) {
            valLL = leftCue
            valLR = ctrLeftCue
            cuesL = []
        } else {
            (valLL,valLR, cuesL) = await try recursiveScan(frameProvider: frameProvider, left:left, right:mid, leftCue: leftCue,rightCue: ctrLeftCue, accuracy: accuracy)
        }
        
        if (ctrRightCue.tag == rightCue.tag) {
            valRL = ctrRightCue
            valRR = ctrRightCue
            cuesR = []
        } else if (mid + 1 + accuracy >= right) {
            valRL = ctrRightCue
            valRR = rightCue
            cuesR = []
        } else {
            (valRL,valRR, cuesR) = await try recursiveScan(frameProvider: frameProvider, left:mid+1, right:right, leftCue: ctrRightCue,rightCue: rightCue, accuracy: accuracy)
        }
        
        
        // LL == LR == RL == RR
        // consume whole span, add no cues
        if (valLL.tag == valLR.tag) && (valLR.tag == valRL.tag) && (valRL.tag == valRR.tag) {
            return (valLL,valLL,cuesL+cuesR)
        }
        
        // LL == LR == RL != RR
        // consume LR and RL, and return LL and RR
        else if (valLL.tag == valLR.tag) && (valLR.tag == valRL.tag) && (valRL.tag != valRR.tag) {
            return (valLL,valRR,cuesL+cuesR)
        }
        // LL != LR == RL != RR
        // add LR, consume RL, reeturn LL and RR
        else if (valLL.tag != valLR.tag) && (valLR.tag == valRL.tag) && (valRL.tag != valRR.tag) {
            incrementCuesFound()
            return (valLL,valRR,cuesL + [valLR] + cuesR)
        }
        
        // LL != LR == RL == RR
        // return LL, add LR, consuem RL and RR
        else if (valLL.tag != valLR.tag) && (valLR.tag == valRL.tag) && (valRL.tag == valRR.tag) {
            return (valLL,valLR,cuesL + cuesR)
        }
        
        // LL != LR != RL == RR
        // return LL and RL, add LR, consuem RR
        else if (valLL.tag != valLR.tag) && (valLR.tag != valRL.tag) && (valRL.tag == valRR.tag) {
            incrementCuesFound()
            return (valLL,valRL,cuesL + [valLR] + cuesR)
        }
        
        // LL == LR != RL == RR
        // consume LR consume RR, return LL RL
        else if (valLL.tag == valLR.tag) && (valLR.tag != valRL.tag) && (valRL.tag == valRR.tag) {
            return (valLL,valRL, cuesL + cuesR)
        }
        
        // LL == LR != RL != RR
        // add LR and RL, return LL and RR
        else if (valLL.tag == valLR.tag) && (valLR.tag != valRL.tag) && (valRL.tag != valRR.tag) {
            incrementCuesFound()
            return (valLL,valRR,cuesL + [valRL] + cuesR)
        }
        // else nothing equals anything - LL != LR != RL != RR
        else {
            incrementCuesFound()
            incrementCuesFound()
            return (valLL,valRR,cuesL+[valLR,valRL] + cuesR)
        }
    }
    
    func execute() async throws {
        
        
        let frameProvider = try await FrameProvider(URL: self.url)
        
        let size = frameProvider.size
        
        var cues: [Cue] = []
        //print("devourer - beginning execution \(Date())")
        
        
        let left:Int64 = 0
        let right:Int64 = frameProvider.lengthInFrames - 1
        
        for i in 1 ... (self.batchCount) {
            var batch = Batch()
            batch.index = i
            let batchSize = (frameProvider.lengthInFrames - 1)/Int64(self.batchCount)
            batch.start = Int64(i-1) * batchSize
            batch.end = Int64(i) * batchSize - 1
            batch.frameProvider = await try frameProvider.clone()
            self.batches.append(batch)
        }
       
        cues = try await withThrowingTaskGroup(of: [Cue].self, returning: [Cue].self) { taskGroup in
            for batch in batches {
                taskGroup.addTask {
                    // print("BATCH:")
                    // print(batch)
                    
                    let firstBuff = try await frameProvider.getFrame(index: batch.start)
                    let lastBuff = try await frameProvider.getFrame(index: batch.end)
                    
                    if (firstBuff == nil || lastBuff == nil) {
                        //break;
                        return []
                    }
                    
                    let previousSpanCue = cues.last
                    
                    let firstCue = try await self.getCueForBuffer(buffer: firstBuff!)
                    let lastCue = try await self.getCueForBuffer(buffer: lastBuff!)
                    var localCues: [Cue] = []
                    
                    if (firstCue.tag == lastCue.tag) {
                        // print("Shortcircuiting")
                        // print(firstCue)
                        // print(lastCue)
                        
                        if (previousSpanCue == nil) || (previousSpanCue!.tag != firstCue.tag) {
                            localCues.append(firstCue)
                        }
                    } else {
                        let (firstSpan,lastSpan,foundCues) = await try self.recursiveScan(frameProvider:batch.frameProvider!, left: batch.start, right: batch.end, leftCue: firstCue, rightCue: lastCue,accuracy: self.skipFrames)
                        
                        if (previousSpanCue == nil) || (previousSpanCue!.tag != firstSpan.tag) {
                            //print("PreAdding \(firstSpan.tag):\(firstSpan.time)")
                            localCues.append(firstSpan)
                        }
                        localCues = localCues + foundCues
                        
                        if (lastSpan.tag != firstSpan.tag) {
                            //print("PostAdding \(lastSpan.tag):\(lastSpan.time.value)")
                            localCues.append(lastSpan)
                        }
                        //let tags = cues.map {$0.tag}
                        //print ("cues at end of batch: \(tags)")
                    }
                    //}
                    return localCues
                }
            }
            
            var cueTask: [Cue] = []
            for try await result in taskGroup {
                cueTask.append(contentsOf:result)
            }
            return cueTask
        }

        
        progressMsg("devourer - finished scan")
        
        var chapters:[Chapter] = []
        var lastCueTag = ""
        
        cues.sort(by: {$0.time.value < $1.time.value})
        
        for cue in cues
        {
            // Reduce out blank tags or consecutive duplicates
            if ((cue.tag != lastCueTag) && (cue.tag != "")) {
                lastCueTag = cue.tag
                let chapter = Chapter(time: cue.time, title: cue.tag)
                chapters.append(chapter)
            }
        }
        
        //print("chapters: (count: \(chapters.count)):\(chapters)")
        //print("devourer - beginning export \(Date())")
        progressMsg("devourer - beginning export - This could take a while")
        let exporter = VideoExporter(assetURL: self.url, chapters: chapters)
        await exporter.export(to: self.outputUrl) {prog in
            self.progressMsg("exporter - progress: \(round(prog * 100))%")
        }
        //print("devourer - completed export \(Date())")
        progressMsg("devourer - completed export")
    }
}

