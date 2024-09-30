import SwiftUI
import AVKit
import Vision
import Dispatch



struct ContentView: View {
    @State private var selectedFileURL: URL?
    @State private var posterFrame: NSImage?
    @State private var regionOfInterest: CGRect = CGRect(x: 0.1, y: 0.1, width: 0.25, height: 0.25)
    @State private var accuracy: Int = 30
    @State private var isDragging: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var isResizing: Bool = false
    @State private var resizingHandle: ResizingHandle? = nil
    @State private var logMessages: [String] = []
    @State private var isProcessing: Bool = false
    @State private var showROIBox: Bool = false
    @State private var progressDescription: String = ""
    @State private var processingTask: Task<Void, Never>? = nil
    @State private var roiLocation: CGPoint = CGPoint(x: 100, y: 100)
    @State private var roiClickOffset: CGPoint = CGPoint(x: 0.0, y: 0.0)
    @State private var resizeOffset: CGPoint = CGPoint(x: 0.0, y: 0.0)
    @ObservedObject var appState: AppState
    
    enum ResizingHandle {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    var body: some View {
        VStack {

            ZStack {
                
                Button("Choose Movie File") {
                    chooseMovieFile()
                }
                .padding()
                .disabled(isProcessing)
                
                
                if let posterFrame = posterFrame {
                    Image(nsImage: posterFrame)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .border(Color.white)
                        .overlay(GeometryReader { geometry in
                            Rectangle()
                                .stroke((isResizing || isDragging) ? Color.yellow : Color.red, lineWidth: 2)
                                .background(Color.red.opacity(0.01))
                                .frame(width: regionOfInterest.width * geometry.size.width, height: regionOfInterest.height * geometry.size.height)
                                .gesture(DragGesture(coordinateSpace: CoordinateSpace.named("parent"))
                                    .onChanged { value in
                                        startDragging(value: value, geometry: geometry)
                                    }
                                    .onEnded { _ in
                                        isDragging = false
                                    }
                                ).position(x:regionOfInterest.midX * geometry.size.width, y:regionOfInterest.midY * geometry.size.height)
                                .overlay(resizingHandles(geometry: geometry))
                        }.coordinateSpace(name: "parent")
                        ).aspectRatio(CGSize(width: 16, height: 9), contentMode: .fit)
                }

                
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                //.padding()
                .background(Color.black.opacity(0.5))
                .aspectRatio(CGSize(width: 16, height: 9), contentMode: .fit)
            
            Spacer()
            
            HStack {
                /*Label("Accuracy:", systemImage: "")
                
                TextField("", value: $accuracy, formatter: NumberFormatter())
                    .frame(width: 40)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .fixedSize(horizontal: true, vertical: true)
                    .disabled(isProcessing)
                */

                Text(progressDescription)
                
                Spacer()
                
                Button("Scan & Save") {
                    scanAndSave()
                }
                .disabled(selectedFileURL == nil || regionOfInterest.isEmpty || isProcessing)
                .padding()
                
               /* if isProcessing {
                    Button("Cancel") {
                        cancelProcessing()
                    }
                    .padding()
                } */
                
            }

        }.frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .foregroundColor(Color.white)
            .disabled(isProcessing)
            .popover(isPresented: $showROIBox,attachmentAnchor:  .point(UnitPoint(x: 320, y: 320))) {
                Text("Move the red box to the area tobe scanned for the cue numbers.  You must include the word 'Cue' in your scan area and there must be a space between 'Cue' and the cue number.")
                Button("OK", role: .cancel) {showROIBox.toggle()}
            }.padding()
            .onReceive(appState.$importTrigger) { val in
                if val {
                    chooseMovieFile()
                }
            }
    }
    
    private func chooseMovieFile() {
        let dialog = NSOpenPanel()
        dialog.title = "Choose a QuickTime movie (.mov) file"
        dialog.allowedFileTypes = ["mov"]
        if dialog.runModal() == .OK, let url = dialog.url {
            selectedFileURL = url
            loadPosterFrame(from: url)
        }
    }

    private func loadPosterFrame(from url: URL) {
        let asset = AVAsset(url: url)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        
        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, result, error in
            if let error = error {
                logMessages.append("Error generating poster frame: \(error.localizedDescription)")
                return
            }
            if result == .succeeded, let image = image {
                posterFrame = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                showROIBox = true
                DispatchQueue.main.async() {
                    let alert = NSAlert()
                    alert.alertStyle = .informational
                    alert.messageText = "Move the red box to cover the area to scan for cue numbers.  The box should include the word 'Cue' and be as small as possible to increase scan speed."
                    alert.runModal()
                }
            }
        }
    }
    
    private func resizingHandles(geometry: GeometryProxy) -> some View {
        return Group {
            let handleSize: CGFloat = 10
            ForEach([ResizingHandle.topLeft, .topRight, .bottomLeft, .bottomRight], id: \.self) { handle in
                Circle()
                    .fill(Color.red)
                    .frame(width: handleSize, height: handleSize)
                    .position(resizingHandlePosition(geometry: geometry, handle: handle, handleSize: handleSize))
                    .gesture(DragGesture(coordinateSpace: CoordinateSpace.named("zstack"))
                        .onChanged { value in
                            isResizing = true
                            resizeRectangle(geometry: geometry, DragGestureValue: value, handle: handle)
                        }
                        .onEnded { _ in
                            isResizing = false
                        }
                    )
            }
        }
    }
    
    private func resizingHandlePosition(geometry: GeometryProxy, handle: ResizingHandle, handleSize: CGFloat) -> CGPoint {
        switch handle {
        case .topLeft:
            return CGPoint(x: regionOfInterest.minX * geometry.size.width, y: regionOfInterest.minY * geometry.size.height)
        case .topRight:
            return CGPoint(x: regionOfInterest.maxX * geometry.size.width, y: regionOfInterest.minY * geometry.size.height)
        case .bottomLeft:
            return CGPoint(x: regionOfInterest.minX * geometry.size.width, y: regionOfInterest.maxY * geometry.size.height)
        case .bottomRight:
            return CGPoint(x: regionOfInterest.maxX * geometry.size.width, y: regionOfInterest.maxY * geometry.size.height)
        }
    }
    
    private func startDragging(value: DragGesture.Value,geometry: GeometryProxy) {
        if (!isDragging) {
            isDragging = true
            roiClickOffset = CGPoint(x:value.startLocation.x - regionOfInterest.midX * geometry.size.width, y: value.startLocation.y - regionOfInterest.midY * geometry.size.height)
        }
        
        let roiWidthPx = regionOfInterest.size.width * geometry.size.width
        let roiHeightPx = regionOfInterest.size.height * geometry.size.height
        
        var newX = max(0.0,min(geometry.size.width - roiWidthPx, (value.location.x - roiClickOffset.x) - (roiWidthPx / 2.0)))
        var newY = max(0.0,min(geometry.size.height - roiHeightPx, (value.location.y - roiClickOffset.y) - (roiHeightPx / 2.0)))
        
        
        regionOfInterest.origin = CGPoint(x: newX / geometry.size.width, y: newY / geometry.size.height)
    }
    
    private func resizeRectangle(geometry: GeometryProxy, DragGestureValue value: DragGesture.Value, handle: ResizingHandle) {
        
        let minWidth: CGFloat = 20
        let minHeight: CGFloat = 20
        var newX = value.location.x
        var newY = value.location.y
        var sizeY: CGFloat = 0.0
        var sizeX: CGFloat = 0.0
        
        let roiMinX = regionOfInterest.minX * geometry.size.width
        let roiMaxX = regionOfInterest.maxX * geometry.size.width
        let roiMinY = regionOfInterest.minY * geometry.size.height
        let roiMaxY = regionOfInterest.maxY * geometry.size.height
        
        print("X: \(value.location.x), Y: \(value.location.y)")
        
        switch handle {
        case .topLeft:
            print("TopLeft")
            newX = max(0.0,newX)
            newY = max(0.0,newY)
            sizeX = roiMaxX - newX
            sizeY = roiMaxY - newY
            
        case .topRight:
            print("TopRight")
            newX = min(geometry.size.width, roiMinX)
            newY = max(0.0,min(newY,geometry.size.height))
            
            sizeX = (max(roiMinX + minWidth,value.location.x)) - roiMinX
            sizeY = roiMaxY - newY
            
        case .bottomLeft:
            print("BottomLeft")
            newX = max(0.0,newX)
            newY = min(geometry.size.height, roiMinY)
            
            sizeX = roiMaxX - newX
            sizeY = max(roiMinY + minHeight,value.location.y) - roiMinY
            
        case .bottomRight:
            print("BottomRight")
            newX = roiMinX
            newY = roiMinY
            
            sizeX = max(roiMinX + minWidth,value.location.x) - roiMinX
            sizeY = max(roiMinY + minHeight,value.location.y) - roiMinY
        }
        
        if (sizeX <= minWidth) {
            newX = roiMinX
            sizeX = regionOfInterest.width * geometry.size.width
        }
        
        if (sizeY <= minHeight) {
            newY = roiMinY
            sizeY = regionOfInterest.height * geometry.size.height
        }
        
        let newOrigin = CGPoint(x: newX / geometry.size.width, y: newY / geometry.size.height)
        let newSize = CGSize(width: sizeX / geometry.size.width, height: sizeY / geometry.size.height)
        regionOfInterest = CGRect(origin: newOrigin, size: newSize)
        
        print("ROI: \(regionOfInterest)")
        print("GEOMETRY SIZE: \(geometry.size)")
        
    }
    
    private func scanAndSave() {
        guard let fileURL = selectedFileURL else { return }
        let existingDirectory = fileURL.deletingLastPathComponent()
        var fileName = fileURL.lastPathComponent
        var filenamePieces = fileName.split(separator: ".")
        var newName = ""
        
        if filenamePieces.count > 1 {
            let ext = filenamePieces.removeLast()
            let base = filenamePieces.joined(separator: ".")
            newName = base + "_devoured." + String(ext)
        }   else {
            newName = fileName + "_devoured"
        }
        
        let savePanel = NSSavePanel()
        savePanel.allowedFileTypes = ["mov", "mp4"]
        savePanel.directoryURL = existingDirectory
        savePanel.nameFieldStringValue = String(newName)
        savePanel.begin { response in
            if response == .OK, let saveURL = savePanel.url {
                logMessages.append("Processing movie and saving to: \(saveURL.path)")
                startProcessing(saveURL: saveURL)
            }
        }
    }
    
    private func startProcessing(saveURL: URL) {
        isProcessing = true
        
        processingTask = Task {
            // we flip the ROI because the origin is bottom left, not top left, for Vision APIs
            let flippedRoi = NormalizedRect(x: regionOfInterest.minX, y: (1.0 - regionOfInterest.maxY), width: regionOfInterest.width, height: regionOfInterest.height)
            
            let dv = Devourer(roi: flippedRoi, url: selectedFileURL!, outputUrl: saveURL) {progress in
                self.progressDescription = progress
            }
            do {
                await try dv.execute()
                DispatchQueue.main.async() {
                    let alert = NSAlert()
                    alert.alertStyle = .informational
                    alert.messageText = "Scanning and Encoding Complete."
                    alert.runModal()
                }
                isProcessing = false
                self.progressDescription = ""
                posterFrame = nil
            } catch {
                DispatchQueue.main.async() {
                    let alert = NSAlert()
                    alert.alertStyle = .informational
                    alert.messageText = "Encounterd an error while processing. \(error)"
                    alert.runModal()
                }
                isProcessing = false
                self.progressDescription = ""
                posterFrame = nil
            }
        }
    }
    
    private func cancelProcessing() {
        isProcessing = false
        processingTask?.cancel()
    }
}



#Preview {
    let appState = AppState()
    ContentView(appState: appState)
}
