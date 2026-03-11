# Production CDM - Power BI Enterprise Analytics

This repository contains the metadata, report definitions, and deployment automation for the **Production Common Data Model (CDM)**. It leverages the Power BI Project (PBIP) format to enable professional software engineering workflows, including version control, branching, and CI/CD.

## 📁 Repository Structure

-   **`Production CDM.SemanticModel/`**: Contains the TMDL-based definitions for the semantic model (tables, measures, relationships). This is the source of truth for the data model.
-   **`Production CDM.Report/`**: Contains the `report.json` and visual definitions. This is the source of truth for the report layout.
-   **`deploy-pbi.ps1`**: Local PowerShell script for manual deployments from a workstation.
-   **`azure-pipelines.yml`**: CI/CD pipeline definition for automated deployments via Azure DevOps.
-   **`instructions.md`**: Foundational deployment mandates and environment-specific rules.

## 🚀 Development Workflow

This project follows a strict **Research -> Strategy -> Execution** lifecycle.

### 1. Feature Branching
Always create a feature branch for changes:
`git checkout -b feature/your-feature-name`

### 2. Working with PBIP
To modify the report or model:
1.  Open the `definition.pbir` (in the `.Report` folder) or `definition.pbism` (in the `.SemanticModel` folder) using **Power BI Desktop**.
2.  Make your changes and **Save**.
3.  Power BI Desktop will update the text files in the folders.
4.  Commit only the text-based changes. **Do not track .pbix files.**

### 3. Report Page Mandate
Per `instructions.md`, all reports deployed from feature branches to the **Dev** workspace must be limited to the **first 4 pages**.
-   The automated pipeline and `deploy-pbi.ps1` script are designed to respect the local `report.json` configuration.

## 🛠 Deployment

### Automated (CI/CD)
Pushing to `feature/*` or `Production-Main` triggers the Azure DevOps pipeline.
-   The pipeline dynamically packages the PBIP folders into a deployment archive.
-   It uses a Service Principal to authenticate and push to the target workspace.

### Manual
Use the provided script for testing:
```powershell
.\deploy-pbi.ps1 -TargetEnv Dev -BranchName "MyFeature"
```
*Note: This script requires the `MicrosoftPowerBIMgmt` module and uses interactive authentication.*

## 🔐 Environment Configuration
-   **Dev Workspace**: `2696b15d-427e-437b-ba5a-ca8d4fb188dd`
-   **Prod Workspace**: `c05c8a73-79ee-4b7f-b798-831b5c260f1b`

## 📝 Governance
-   **Source of Truth**: The text-based definitions in the folders are the primary record.
-   **Binary Files**: `.pbix` files are ignored to keep the repository lean and prevent merge conflicts in binary data.
-   **Friendly Names**: Always refer to datasets using business-friendly names as mapped in `Production CDM UAT.md`.
