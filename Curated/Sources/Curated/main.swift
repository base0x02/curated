import Foundation

if CommandLine.arguments.contains("--scheduled-download") {
    setvbuf(stdout, nil, _IOLBF, 0)
    exit(HeadlessRunner.run())
} else {
    CuratedApp.main()
}
