flowchart TD
    %% Distribution Layer
    subgraph "Distribution & Hosting"
        direction TB
        Vercel["Vercel CDN/Edge"]:::infra
        NaiveEntry["naive.sh (Installer Entry Point)"]:::shell
        Vercel -->|"fetch script"| NaiveEntry
    end

    %% CI/CD Layer
    subgraph "CI/CD Pipeline"
        direction TB
        GitHubRepo["GitHub Repository"]:::external
        WorkflowsDir[".github/workflows (CI Workflows Directory)"]:::external
        BuildYML["build.yml (CI/CD Pipeline Definition)"]:::external
        GitHubActions["GitHub Actions"]:::infra
        GitHubRepo -->|triggers CI| WorkflowsDir
        WorkflowsDir --> BuildYML
        BuildYML -->|executes| GitHubActions
    end

    %% Installer Scripts
    subgraph "Installer Scripts"
        direction TB
        GoInstall["go.sh (Go Toolchain Installer)"]:::shell
        XCaddyBuild["xcaddy build step"]:::binary
        CaddyBuild["caddy.sh (Caddy Build Script)"]:::shell
        NaiveEntry -->|calls| GoInstall
        NaiveEntry -->|invokes| XCaddyBuild
        XCaddyBuild -->|wrapped by| CaddyBuild
    end

    %% Installer Execution on Host
    subgraph "Host Installation"
        direction TB
        GoPPA["Go PPA / GitHub"]:::external
        USRCaddy["/usr/bin/caddy (Installed Binary)"]:::binary
        CaddyFile["/etc/caddy/Caddyfile"]:::service
        SystemdUnit["systemd Service Unit"]:::service
        NaiveEntry -->|calls| GoInstall
        GoInstall -->|install Go from| GoPPA
        CaddyBuild -->|installs binary| USRCaddy
        NaiveEntry -->|"write config"| CaddyFile
        NaiveEntry -->|"write unit"| SystemdUnit
        SystemdUnit -->|start service| USRCaddy
    end

    %% Runtime Components
    subgraph "Runtime"
        direction TB
        CaddyService["Caddy Web Server (forwardproxy)"]:::service
        ClientApps["Client Apps (e.g., Browsers, SOCKS5 Clients)"]:::external
        UpstreamProxy["Upstream HTTPS Proxy"]:::external
        USRCaddy -->|runs as| CaddyService
        ClientApps -->|connect SOCKS5| CaddyService
        CaddyService -->|forward to| UpstreamProxy
    end

    %% Documentation
    subgraph "Documentation & Config"
        direction TB
        Readme["README.md (Project Documentation & Usage Guide)"]:::external
        Vercel --> Readme
    end

    %% Click Events
    click NaiveEntry "https://github.com/passeway/naiveproxy/blob/main/naive.sh"
    click GoInstall "https://github.com/passeway/naiveproxy/blob/main/go.sh"
    click CaddyBuild "https://github.com/passeway/naiveproxy/blob/main/caddy.sh"
    click WorkflowsDir "https://github.com/passeway/naiveproxy/tree/main/.github/workflows"
    click BuildYML "https://github.com/passeway/naiveproxy/blob/main/.github/workflows/build.yml"
    click Vercel "https://github.com/passeway/naiveproxy/blob/main/vercel.json"
    click Readme "https://github.com/passeway/naiveproxy/blob/main/README.md"

    %% Styles
    classDef shell fill:#FFEB3B,stroke:#333,stroke-width:1px
    classDef binary fill:#03A9F4,stroke:#333,stroke-width:1px
    classDef service fill:#8BC34A,stroke:#333,stroke-width:1px
    classDef infra fill:#FF9800,stroke:#333,stroke-width:1px
    classDef external fill:#BDBDBD,stroke:#333,stroke-width:1px
