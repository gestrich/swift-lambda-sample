import DeployLocalService
import DeployXcodeFeature

// MARK: - Xcode Progress Printers

func printXcodeBuildProgress(_ progress: XcodeWorkflowState) {
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

func printXcodeStartLambdaProgress(_ progress: XcodeStartLambdaWorkflow.State) {
    switch progress.step {
    case .checkingBuild:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🔍 Checking build...")
        }
    case .building:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🔨 Building Lambda...")
        }
    case .starting:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🚀 Starting Lambda...")
        }
    case .waitingForReady:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("⏳ Waiting for Lambda to be ready...")
        }
    case .complete:
        if case .port(let port) = progress.detail {
            print("✅ Lambda running on port \(port)")
        } else {
            print("✅ Lambda started")
        }
    }
}

func printXcodeStopLambdaProgress(_ progress: XcodeStopLambdaWorkflow.State) {
    switch progress.step {
    case .checking:
        print("🔍 Checking Lambda status...")
    case .stopping:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🛑 Stopping Lambda...")
        }
    case .complete:
        if case .wasRunning(let wasRunning) = progress.detail {
            if wasRunning {
                print("✅ Lambda stopped")
            } else {
                print("ℹ️  Lambda was not running")
            }
        } else {
            print("✅ Lambda stopped")
        }
    }
}

func printXcodeStartServicesProgress(_ progress: XcodeStartServicesWorkflow.State) {
    switch progress.step {
    case .startingDatabase:
        if case .serviceStarted(_) = progress.detail {
            print("✅ PostgreSQL started")
        } else {
            print("🐘 Starting PostgreSQL...")
        }
    case .startingS3:
        if case .serviceStarted(_) = progress.detail {
            print("✅ MinIO S3 started")
        } else {
            print("📦 Starting MinIO S3...")
        }
    case .creatingBucket:
        print("🪣 Creating S3 bucket...")
    case .startingDynamoDB:
        if case .serviceStarted(_) = progress.detail {
            print("✅ DynamoDB started")
        } else {
            print("⚡ Starting DynamoDB...")
        }
    case .complete:
        print("✅ All services started")
    }
}

func printXcodeStopServicesProgress(_ progress: XcodeStopServicesWorkflow.State) {
    switch progress.step {
    case .stoppingDatabase:
        if case .serviceStopped(_) = progress.detail {
            print("✅ PostgreSQL stopped")
        } else {
            print("🐘 Stopping PostgreSQL...")
        }
    case .stoppingS3:
        if case .serviceStopped(_) = progress.detail {
            print("✅ MinIO S3 stopped")
        } else {
            print("📦 Stopping MinIO S3...")
        }
    case .stoppingDynamoDB:
        if case .serviceStopped(_) = progress.detail {
            print("✅ DynamoDB stopped")
        } else {
            print("⚡ Stopping DynamoDB...")
        }
    case .complete:
        print("✅ All services stopped")
    }
}

func printXcodeStartAllProgress(_ progress: XcodeWorkflowState) {
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

func printXcodeStopAllProgress(_ progress: XcodeWorkflowState) {
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

func printXcodeTestProgress(_ progress: XcodeTestWorkflow.State) {
    switch progress.step {
    case .checkingLambda:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🔍 Checking Lambda status...")
        }
    case .testingFileUpload:
        if case .testPassed(let name) = progress.detail {
            print("✅ \(name)")
        } else {
            print("📤 Testing file upload...")
        }
    case .testingFileList:
        if case .testPassed(let name) = progress.detail {
            print("✅ \(name)")
        } else {
            print("📋 Testing file list...")
        }
    case .testingFileDownload:
        if case .testPassed(let name) = progress.detail {
            print("✅ \(name)")
        } else {
            print("📥 Testing file download...")
        }
    case .testingDatabaseInit:
        if case .testPassed(let name) = progress.detail {
            print("✅ \(name)")
        } else {
            print("🗄️  Testing database init...")
        }
    case .complete:
        print("")
        print("✅ All tests passed")
    }
}

func printXcodeCopyConfigProgress(_ progress: XcodeCopyConfigWorkflow.State) {
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

func printXcodeStatusProgress(_ progress: XcodeWorkflowState) {
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
