# Development & Deployment Instructions

## Feature Branch Deployment Rules
For every feature branch that is being added or deployed to the **Dev** workspace, the following process must be followed:

1.  **Source of Truth**: The **PBIP folders** (`.Report` and `.SemanticModel`) are the absolute source of truth. Deployment scripts and pipelines MUST deploy from these folders, not from a static `.pbix` file.
    
2.  **Deployment Type Confirmation**: Always ask the user if the deployment should be:
    *   A **Live Connection Report** (connecting to an existing published semantic model).
    *   A **New Semantic Model** (uploading the local `.SemanticModel` definition/metadata).

3.  **Report Page Reduction**: For every report created or updated via a feature branch, the report definition must be modified to keep **only the first 4 pages**. All other pages must be removed.
    *   This rule applies to **both** Live Connected reports and reports with their own Semantic Model.
    *   The modification should be performed on the `report.json` file within the `.Report` folder before deployment.

## Existing Dev Workspaces
*   **Dev Workspace ID**: `2696b15d-427e-437b-ba5a-ca8d4fb188dd`
*   **Production CDM Dataset ID**: `10ad1784-d53f-4877-b9f0-f77641efbff4`
