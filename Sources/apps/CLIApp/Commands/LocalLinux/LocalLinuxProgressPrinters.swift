import DeployLocalService
import DeployLinuxFeature

// MARK: - Linux Progress Printers

func printLinuxBuildProgress(_ progress: LinuxBuildWorkflow.State) {
    switch progress.step {
    case .cleaning:
        print("🧹 Cleaning build artifacts...")
    case .building:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🐳 Building Lambda for Linux (Docker)...")
        }
    case .complete:
        if case .buildPath(let path) = progress.detail {
            print("✅ Build complete: \(path)")
        } else {
            print("✅ Build complete")
        }
    }
}

func printLinuxStartLambdaProgress(_ progress: LinuxStartLambdaWorkflow.State) {
    switch progress.step {
    case .checkingBuild:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🔍 Checking build...")
        }
    case .starting:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🐳 Starting Lambda container...")
        }
    case .waitingForReady:
        print("⏳ Waiting for Lambda to be ready...")
    case .complete:
        if case .port(let port) = progress.detail {
            print("✅ Lambda container running on port \(port)")
        } else {
            print("✅ Lambda container started")
        }
    }
}

func printLinuxStopLambdaProgress(_ progress: LinuxStopLambdaWorkflow.State) {
    switch progress.step {
    case .checking:
        print("🔍 Checking Lambda container status...")
    case .stopping:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🛑 Stopping Lambda container...")
        }
    case .complete:
        if case .wasRunning(let wasRunning) = progress.detail {
            if wasRunning {
                print("✅ Lambda container stopped")
            } else {
                print("ℹ️  Lambda container was not running")
            }
        } else {
            print("✅ Lambda container stopped")
        }
    }
}

func printLinuxStartServicesProgress(_ progress: LinuxStartServicesWorkflow.State) {
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

func printLinuxStopServicesProgress(_ progress: LinuxStopServicesWorkflow.State) {
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

func printLinuxStartAllProgress(_ progress: LinuxStartAllWorkflow.State) {
    switch progress.step {
    case .startingServices:
        if case .servicesState(let servicesProgress) = progress.detail {
            printLinuxStartServicesProgress(servicesProgress)
        } else {
            print("🔄 Starting services...")
        }
    case .setupNetwork:
        if case .networkState(let networkProgress) = progress.detail {
            printLinuxSetupNetworkProgress(networkProgress)
        } else {
            print("🌐 Setting up Docker network...")
        }
    case .startingLambda:
        if case .lambdaState(let lambdaProgress) = progress.detail {
            printLinuxStartLambdaProgress(lambdaProgress)
        } else {
            print("🔄 Starting Lambda container...")
        }
    case .complete:
        if case .port(let port) = progress.detail {
            print("")
            print("✅ All services and Lambda container running on port \(port)")
        } else {
            print("✅ All services started")
        }
    }
}

func printLinuxStopAllProgress(_ progress: LinuxStopAllWorkflow.State) {
    switch progress.step {
    case .stoppingLambda:
        if case .lambdaState(let lambdaProgress) = progress.detail {
            printLinuxStopLambdaProgress(lambdaProgress)
        } else {
            print("🔄 Stopping Lambda container...")
        }
    case .stoppingServices:
        if case .servicesState(let servicesProgress) = progress.detail {
            printLinuxStopServicesProgress(servicesProgress)
        } else {
            print("🔄 Stopping services...")
        }
    case .complete:
        print("")
        print("✅ All Lambda container and services stopped")
    }
}

func printLinuxTestProgress(_ progress: LinuxTestWorkflow.State) {
    switch progress.step {
    case .checkingLambda:
        if case .output(let text) = progress.detail {
            print("  \(text)")
        } else {
            print("🔍 Checking Lambda container status...")
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

func printLinuxStatusProgress(_ progress: LinuxStatusWorkflow.State) {
    switch progress.step {
    case .checkingLambda:
        print("🔍 Checking Lambda container status...")
    case .checkingS3:
        print("🔍 Checking S3 status...")
    case .checkingDatabase:
        print("🔍 Checking PostgreSQL status...")
    case .checkingDynamoDB:
        print("🔍 Checking DynamoDB status...")
    case .complete:
        if case .status(let status) = progress.detail {
            printStatus(status, mode: "Linux (Container)")
        }
    }
}
