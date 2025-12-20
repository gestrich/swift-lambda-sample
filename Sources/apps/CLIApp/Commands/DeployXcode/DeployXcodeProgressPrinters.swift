import DeployLocalService
import DeployXcodeFeature
import LocalServicesFeature

// MARK: - Xcode Progress Printers

func printXcodeBuildProgress(_ progress: XcodeUseCaseState) {
    switch progress {
    case .building(let buildProgress):
        switch buildProgress.step {
        case .cleaning:
            print("🧹 Cleaning build artifacts...")
        case .building:
            if let output = buildProgress.output {
                print("  \(output)")
            } else {
                print("🔨 Building Lambda for macOS...")
            }
        }
    case .completed:
        print("✅ Build complete")
    default:
        break
    }
}

func printXcodeStartLambdaProgress(_ progress: XcodeUseCaseState) {
    switch progress {
    case .startingLambda(let lambdaProgress):
        switch lambdaProgress.step {
        case .checkingBuild:
            print("🔍 Checking build...")
        case .building:
            print("🔨 Building Lambda...")
        case .starting:
            print("🚀 Starting Lambda...")
        case .waitingForReady:
            print("⏳ Waiting for Lambda to be ready...")
        case .stopping:
            break
        }
    case .completed(let snapshot):
        if snapshot.lambdaState == .running {
            print("✅ Lambda running on port 8080")
        } else {
            print("✅ Lambda started")
        }
    default:
        break
    }
}

func printXcodeStopLambdaProgress(_ progress: XcodeUseCaseState) {
    switch progress {
    case .stoppingLambda:
        print("🛑 Stopping Lambda...")
    case .completed(let snapshot):
        if snapshot.lambdaState == .stopped {
            print("✅ Lambda stopped")
        } else {
            print("ℹ️  Lambda stop completed")
        }
    default:
        break
    }
}

func printXcodeStartServicesProgress(_ progress: XcodeUseCaseState) {
    switch progress {
    case .startingServices(let servicesProgress):
        switch servicesProgress.step {
        case .starting:
            if let service = servicesProgress.currentService {
                switch service {
                case .database:
                    print("🐘 Starting PostgreSQL...")
                case .s3:
                    print("📦 Starting MinIO S3...")
                case .dynamodb:
                    print("⚡ Starting DynamoDB...")
                }
            } else {
                print("🔄 Starting services...")
            }
        case .creatingBucket:
            print("🪣 Creating S3 bucket...")
        default:
            break
        }
    case .completed:
        print("✅ All services started")
    default:
        break
    }
}

func printXcodeStopServicesProgress(_ progress: XcodeUseCaseState) {
    switch progress {
    case .stoppingServices(let servicesProgress):
        if let service = servicesProgress.currentService {
            switch service {
            case .database:
                print("🐘 Stopping PostgreSQL...")
            case .s3:
                print("📦 Stopping MinIO S3...")
            case .dynamodb:
                print("⚡ Stopping DynamoDB...")
            }
        } else {
            print("🔄 Stopping services...")
        }
    case .completed:
        print("✅ All services stopped")
    default:
        break
    }
}

func printXcodeStartAllProgress(_ progress: XcodeUseCaseState) {
    switch progress {
    case .startingServices(let servicesProgress):
        switch servicesProgress.step {
        case .starting:
            if let service = servicesProgress.currentService {
                switch service {
                case .database:
                    print("🐘 Starting PostgreSQL...")
                case .s3:
                    print("📦 Starting MinIO S3...")
                case .dynamodb:
                    print("⚡ Starting DynamoDB...")
                }
            } else {
                print("🔄 Starting services...")
            }
        case .creatingBucket:
            print("🪣 Creating S3 bucket...")
        default:
            break
        }
    case .startingLambda(let lambdaProgress):
        switch lambdaProgress.step {
        case .checkingBuild:
            print("🔍 Checking build...")
        case .building:
            print("🔨 Building Lambda...")
        case .starting:
            print("🚀 Starting Lambda...")
        case .waitingForReady:
            print("⏳ Waiting for Lambda to be ready...")
        case .stopping:
            break
        }
    case .completed(let snapshot):
        print("")
        if snapshot.isAllRunning {
            print("✅ All services and Lambda running on port 8080")
        } else {
            print("✅ Start all workflow completed")
        }
    default:
        break
    }
}

func printXcodeStopAllProgress(_ progress: XcodeUseCaseState) {
    switch progress {
    case .stoppingLambda:
        print("🛑 Stopping Lambda...")
    case .stoppingServices(let servicesProgress):
        if let service = servicesProgress.currentService {
            switch service {
            case .database:
                print("🐘 Stopping PostgreSQL...")
            case .s3:
                print("📦 Stopping MinIO S3...")
            case .dynamodb:
                print("⚡ Stopping DynamoDB...")
            }
        } else {
            print("🔄 Stopping services...")
        }
    case .completed(let snapshot):
        print("")
        if snapshot.isAllStopped {
            print("✅ All Lambda and services stopped")
        } else {
            print("✅ Stop all workflow completed")
        }
    default:
        break
    }
}

func printXcodeTestProgress(_ progress: XcodeUseCaseState) {
    switch progress {
    case .testing(let testProgress):
        switch testProgress.step {
        case .checkingLambda:
            if case .message(let text) = testProgress.result {
                print("  \(text)")
            } else {
                print("🔍 Checking Lambda status...")
            }
        case .testingFileUpload:
            if case .passed(let name) = testProgress.result {
                print("✅ \(name)")
            } else {
                print("📤 Testing file upload...")
            }
        case .testingFileList:
            if case .passed(let name) = testProgress.result {
                print("✅ \(name)")
            } else {
                print("📋 Testing file list...")
            }
        case .testingFileDownload:
            if case .passed(let name) = testProgress.result {
                print("✅ \(name)")
            } else {
                print("📥 Testing file download...")
            }
        case .testingDatabaseInit:
            if case .passed(let name) = testProgress.result {
                print("✅ \(name)")
            } else {
                print("🗄️  Testing database init...")
            }
        }
    case .completed:
        print("")
        print("✅ All tests passed")
    default:
        break
    }
}

func printXcodeCopyConfigProgress(_ progress: XcodeCopyConfigUseCase.State) {
    switch progress.step {
    case .copying:
        if case .copiedFile(let file) = progress.detail {
            print("📄 Copied \(file)")
        } else {
            print("📋 Copying config files...")
        }
    case .complete:
        if case .destinationPath(let path) = progress.detail {
            print("✅ Config copied to \(path)")
        } else {
            print("✅ Config copied")
        }
    }
}

func printXcodeStatusProgress(_ progress: XcodeUseCaseState) {
    switch progress {
    case .checkingStatus(let statusProgress):
        switch statusProgress.step {
        case .checkingLambda:
            print("🔍 Checking Lambda status...")
        case .checkingS3:
            print("🔍 Checking S3 status...")
        case .checkingDatabase:
            print("🔍 Checking PostgreSQL status...")
        case .checkingDynamoDB:
            print("🔍 Checking DynamoDB status...")
        }
    case .completed(let snapshot):
        printStatus(snapshot.serviceStatus, mode: "Mac (Native)")
    default:
        break
    }
}
