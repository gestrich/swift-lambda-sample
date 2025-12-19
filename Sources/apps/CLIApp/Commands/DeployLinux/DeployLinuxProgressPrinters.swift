import DeployLocalService
import DeployLinuxFeature

// MARK: - Linux Progress Printers

func printLinuxBuildProgress(_ progress: LinuxWorkflowState) {
    switch progress {
    case .building(let buildProgress):
        switch buildProgress.step {
        case .cleaning:
            print("🧹 Cleaning build artifacts...")
        case .building:
            if let output = buildProgress.output {
                print("  \(output)")
            } else {
                print("🐳 Building Lambda for Linux (Docker)...")
            }
        }
    case .completed:
        print("✅ Build complete")
    default:
        break
    }
}

func printLinuxStartLambdaProgress(_ progress: LinuxWorkflowState) {
    switch progress {
    case .building(let buildProgress):
        if let output = buildProgress.output {
            print("  \(output)")
        } else {
            print("🔨 Building Lambda...")
        }
    case .startingLambda(let lambdaProgress):
        switch lambdaProgress.step {
        case .starting:
            print("🐳 Starting Lambda container...")
        case .waitingForReady:
            print("⏳ Waiting for Lambda to be ready...")
        case .stopping:
            break
        }
    case .completed:
        print("✅ Lambda container started")
    default:
        break
    }
}

func printLinuxStopLambdaProgress(_ progress: LinuxWorkflowState) {
    switch progress {
    case .stoppingLambda:
        print("🛑 Stopping Lambda container...")
    case .completed:
        print("✅ Lambda container stopped")
    default:
        break
    }
}

func printLinuxStartServicesProgress(_ progress: LinuxWorkflowState) {
    switch progress {
    case .startingServices(let servicesProgress):
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
    case .completed:
        print("✅ All services started")
    default:
        break
    }
}

func printLinuxStopServicesProgress(_ progress: LinuxWorkflowState) {
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

func printLinuxStartAllProgress(_ progress: LinuxWorkflowState) {
    switch progress {
    case .startingServices(let servicesProgress):
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
    case .settingUpNetwork(let networkProgress):
        if let message = networkProgress.message {
            print("  ✓ \(message)")
        } else {
            switch networkProgress.step {
            case .creatingNetwork:
                print("🌐 Creating Docker network...")
            case .connectingContainers:
                print("🔗 Connecting containers to network...")
            }
        }
    case .startingLambda(let lambdaProgress):
        switch lambdaProgress.step {
        case .starting:
            print("🐳 Starting Lambda container...")
        case .stopping:
            print("🛑 Stopping Lambda container...")
        case .waitingForReady:
            print("⏳ Waiting for Lambda to be ready...")
        }
    case .completed(let snapshot):
        print("")
        if snapshot.isAllRunning {
            print("✅ All services and Lambda container started")
        } else {
            print("✅ Workflow complete")
        }
    default:
        break
    }
}

func printLinuxStopAllProgress(_ progress: LinuxWorkflowState) {
    switch progress {
    case .stoppingLambda(let lambdaProgress):
        switch lambdaProgress.step {
        case .stopping:
            print("🛑 Stopping Lambda container...")
        case .starting, .waitingForReady:
            break
        }
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
            print("✅ All Lambda container and services stopped")
        } else {
            print("✅ Workflow complete")
        }
    default:
        break
    }
}

func printLinuxTestProgress(_ progress: LinuxWorkflowState) {
    switch progress {
    case .testing(let testProgress):
        switch testProgress.step {
        case .checkingLambda:
            if case .message(let text) = testProgress.result {
                print("  \(text)")
            } else {
                print("🔍 Checking Lambda container status...")
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

func printLinuxCopyConfigProgress(_ progress: LinuxCopyConfigWorkflow.State) {
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

func printLinuxSetupNetworkProgress(_ progress: LinuxSetupNetworkWorkflow.State) {
    switch progress.step {
    case .creatingNetwork:
        switch progress.detail {
        case .networkCreated(let name):
            print("✅ Network '\(name)' created")
        case .output(let message):
            print("  ✓ \(message)")
        default:
            print("🌐 Creating Docker network...")
        }
    case .connectingContainers:
        switch progress.detail {
        case .containerConnected(let name):
            print("  🔗 Connected \(name)")
        case .containerSkipped(let name, let reason):
            print("  ⚠️  Skipped \(name) (\(reason))")
        case .output(let message):
            print("  ✓ \(message)")
        default:
            print("🔗 Connecting containers to network...")
        }
    case .complete:
        print("✅ Docker network setup complete")
    }
}

func printLinuxRunInteractiveProgress(_ progress: LinuxRunInteractiveWorkflow.State) {
    switch progress.step {
    case .preparing:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🔧 Preparing interactive container...")
        }
    case .launching:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🐳 Launching interactive container...")
        }
    case .complete:
        print("✅ Interactive session ended")
    }
}

func printLinuxStatusProgress(_ progress: LinuxWorkflowState) {
    switch progress {
    case .checkingStatus(let statusProgress):
        switch statusProgress.step {
        case .checkingLambda:
            print("🔍 Checking Lambda container status...")
        case .checkingS3:
            print("🔍 Checking S3 status...")
        case .checkingDatabase:
            print("🔍 Checking PostgreSQL status...")
        case .checkingDynamoDB:
            print("🔍 Checking DynamoDB status...")
        }
    case .completed(let snapshot):
        printStatus(snapshot.serviceStatus, mode: "Linux (Container)")
    default:
        break
    }
}
