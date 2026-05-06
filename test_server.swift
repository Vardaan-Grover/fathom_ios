import Foundation
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator
import ReadiumAdapterGCDWebServer

let client = DefaultHTTPClient()
let retriever = AssetRetriever(httpClient: client)
let server = try! GCDHTTPServer(assetRetriever: retriever)
print(server)
