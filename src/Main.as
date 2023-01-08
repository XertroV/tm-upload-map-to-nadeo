[Setting name="Auto upload on map start"]
bool Setting_AutoUpload = false;

string currMapUid;

bool HasPermissions {
    get {
        return Permissions::CreateAndUploadMap();
    }
}

void Main() {
    if (!HasPermissions) {
        Notify("Note: you don't have permissions to upload maps. This plugin will do nothing.");
    }
}

/** Called every frame. `dt` is the delta time (milliseconds since last frame).
*/
void Update(float dt) {
    if (!HasPermissions) return;
    auto app = cast<CGameManiaPlanet>(GetApp());
    if ((app.RootMap is null && currMapUid != "")) {
        currMapUid = "";
        currMapStatus = MapStatus::NoMap;
    } else if (app.RootMap !is null && app.RootMap.MapInfo.MapUid != currMapUid) {
        currMapUid = app.RootMap.MapInfo.MapUid;
        startnew(UpdateMapStatus);
        if (Setting_AutoUpload) startnew(WaitForCheckAndAutoUploadIfNotUploaded);
    }
}

enum MapStatus {
    NoMap,
    NotChecked,
    Checking,
    Uploading,
    Uploaded,
    NotUploaded,
    Unknown,
    Editing
}

MapStatus currMapStatus = MapStatus::NotChecked;

void UpdateMapStatus() {
    // check if the current UID is uploaded and cache result
    currMapStatus = MapStatus::NotChecked;
    if (!HasPermissions) return;
    sleep(100);
    currMapStatus = MapStatus::Checking;
    auto app = cast<CGameManiaPlanet>(GetApp());
    if (app.Editor !is null) {
        currMapStatus = MapStatus::Editing;
        return;
    }
    while (app.MenuManager is null || app.MenuManager.MenuCustom_CurrentManiaApp is null) yield();
    auto mccma = app.MenuManager.MenuCustom_CurrentManiaApp;
    while (mccma.DataFileMgr is null || mccma.UserMgr is null || mccma.UserMgr.Users.Length < 1) yield();
    auto mapGetReq = mccma.DataFileMgr.Map_NadeoServices_GetFromUid(mccma.UserMgr.Users[0].Id, currMapUid);
    while (mapGetReq.IsProcessing) yield();
    if (mapGetReq.HasFailed) {
        if (mapGetReq.ErrorDescription.Contains("Unknown map")) {
            currMapStatus = MapStatus::NotUploaded;
        } else {
            NotifyError("Checking map failed: " + mapGetReq.ErrorCode + ", " + mapGetReq.ErrorType + ", " + mapGetReq.ErrorDescription);
            currMapStatus = MapStatus::Unknown;
        }
    } else if (mapGetReq.HasSucceeded) {
        bool mapExists = mapGetReq.Map !is null;
        if (!mapExists) {
            currMapStatus = MapStatus::NotUploaded;
        } else {
            currMapStatus = MapStatus::Uploaded;
        }
    } else {
        currMapStatus = MapStatus::Unknown;
    }
}

void WaitForCheckAndAutoUploadIfNotUploaded() {
    while (currMapStatus == MapStatus::NotChecked || currMapStatus == MapStatus::Checking) yield();
    if (currMapStatus == MapStatus::NotUploaded) UploadCurrMap();
}

const string MapStatusText() {
    switch (currMapStatus) {
        case MapStatus::NoMap: return "";
        case MapStatus::NotChecked: return "--";
        case MapStatus::Checking: return LoadingIconStr();
        case MapStatus::Uploading: return Icons::Upload + " " + LoadingIconStr();
        case MapStatus::Uploaded: return Icons::Check;
        case MapStatus::NotUploaded: return "\\$<\\$2f2" + Icons::Upload + "\\$>";
        case MapStatus::Unknown: return Icons::Exclamation;
        case MapStatus::Editing: return Icons::Pencil;
    }
    return "??";
}

const string LoadingIconStr() {
    auto t = (Time::Now / 333) % 3;
    if (t == 0) return Icons::HourglassStart;
    if (t == 1) return Icons::HourglassHalf;
    return Icons::HourglassEnd;
}


void UploadMap(const string &in uid) {
    if (!Permissions::CreateAndUploadMap()) {
        NotifyError("Refusing to upload maps because you are missing the CreateAndUploadMap permissions.");
        return;
    }
    currMapStatus = MapStatus::Uploading;
    trace('UploadMapFromLocal: ' + uid);
    auto app = cast<CGameManiaPlanet>(GetApp());
    auto cma = app.MenuManager.MenuCustom_CurrentManiaApp;
    auto dfm = cma.DataFileMgr;
    auto userId = cma.UserMgr.Users[0].Id;
    yield();
    auto regScript = dfm.Map_NadeoServices_Register(userId, uid);
    while (regScript.IsProcessing) yield();
    if (regScript.HasFailed) {
        NotifyError("Uploading map failed: " + regScript.ErrorType + ", " + regScript.ErrorCode + ", " + regScript.ErrorDescription);
        currMapStatus = MapStatus::Unknown;
        return;
    }
    if (regScript.HasSucceeded) {
        trace("UploadMapFromLocal: Map uploaded: " + uid);
        currMapStatus = MapStatus::Uploaded;
    }
    dfm.TaskResult_Release(regScript.Id);
}


void Notify(const string &in msg) {
    UI::ShowNotification(Meta::ExecutingPlugin().Name, msg);
    trace("Notified: " + msg);
}

void NotifyError(const string &in msg) {
    UI::ShowNotification(Meta::ExecutingPlugin().Name, msg);
    warn("Notified: " + msg);
}

const string PluginNameMenu = Icons::Upload + " \\$z" + Meta::ExecutingPlugin().Name;

/** Render function called every frame intended only for menu items in `UI`. */
void RenderMenu() {
    if (UI::MenuItem(PluginNameMenu, MapStatusText(), false, currMapStatus == MapStatus::NotUploaded)) {
        if (!HasPermissions) return;
        if (currMapStatus != MapStatus::NotUploaded) return;
        startnew(UploadCurrMap);
    }
}

void UploadCurrMap() {
    UploadMap(currMapUid);
}
