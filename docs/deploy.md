flowchart TD
    DEV["Developer\nazd deploy"]

    subgraph LOCAL["Local Machine"]
        YAML["azure.yaml\n(service: web\nhost: appservice\ndocker: ./src/Dockerfile)"]
        SRC["./src/\n(source code + Dockerfile)"]
    end

    subgraph AZURE["Azure — West US 3"]
        subgraph ACR["Container Registry\ncr4uz7gnv4ukkp2"]
            TASK["ACR Task\n(remote build)"]
            IMG["Image\nweb:latest"]
        end

        subgraph APPSVC["App Service\napp-4uz7gnv4ukkp2"]
            MI["System-Assigned\nManaged Identity\n(AcrPull role)"]
            CONTAINER["Running Container\n:80"]
        end
    end

    DEV -->|"reads"| YAML
    DEV -->|"uploads build context"| TASK
    SRC -->|"sent as build context"| TASK
    TASK -->|"executes Dockerfile\n(SDK build → runtime)"| IMG
    IMG -->|"pull via managed identity\n(no credentials)"| MI
    MI --> CONTAINER
