// [Setting name="Auto upload maps (WARNING)" description="When you load a map (outside of the editor) that is not uploaded, it will be automatically uploaded. This may have unintended consequences, however, it is probably very useful for Bingo."]
// bool S_AutoUpload = false;

[Setting name="Refresh records on upload" description="This will alter the manialink for the records UI element. While this works currently, a future Nadeo update might break this feature. If you ever get script errors when the records should be refreshed, disable this setting."]
bool S_RefreshRecords = true;

string currMapUid, currMapName;

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
        currMapName = "None";
        currMapStatus = MapStatus::NoMap;
    } else if (app.RootMap !is null && app.RootMap.MapInfo.MapUid != currMapUid) {
        currMapUid = app.RootMap.MapInfo.MapUid;
        currMapName = ColoredString(app.RootMap.MapInfo.Name);
        startnew(UpdateMapStatus);
        // if (S_AutoUpload) startnew(WaitForCheckAndAutoUploadIfNotUploaded);
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

// void WaitForCheckAndAutoUploadIfNotUploaded() {
//     while (currMapStatus == MapStatus::NotChecked || currMapStatus == MapStatus::Checking) yield();
//     if (currMapStatus == MapStatus::NotUploaded) {
//         Notify("Automatically uploading map to Nadeo: " + currMapName);
//         UploadCurrMap();
//     }
// }

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
        Notify("Uploaded map: " + currMapName);
        currMapStatus = MapStatus::Uploaded;
        startnew(RefreshRecords);
    }
    dfm.TaskResult_Release(regScript.Id);
}


void RefreshRecords() {
    if (!S_RefreshRecords) return;
    try {
        // patch the maniascript so that it thinks the map is always available -- attempting to set Race_Record_MapAvailaibleOnNadeoServices did not seem to work.
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        for (uint i = 0; i < cmap.UILayers.Length; i++) {
            auto layer = cmap.UILayers[i];
            bool isRecords = layer.ManialinkPageUtf8.SubStr(0, 100).Contains('<manialink name="UIModule_Race_Record" version="3">');
            if (!isRecords) continue;
            // we want to replace all *usages* of the variable `_MapAvailaibleOnNadeoServices` with `True`, so temporarily replace conflicting parts of the ML code.
            auto newML = layer.ManialinkPageUtf8
                .Replace('Race_Record_MapAvailaibleOnNadeoServices', '__RR_MAPAVAILABLE_CLIENTUI__')
                .Replace('Boolean _MapAvailaibleOnNadeoServices,', '__FUNC_ARG_MAPAVAILABLE__')
                .Replace('_MapAvailaibleOnNadeoServices', 'True')
                .Replace('__FUNC_ARG_MAPAVAILABLE__', 'Boolean _MapAvailaibleOnNadeoServices,')
                .Replace('__RR_MAPAVAILABLE_CLIENTUI__', 'Race_Record_MapAvailaibleOnNadeoServices');
            layer.ManialinkPage = newML;
            break;
        }
    } catch {
        warn("Failed to refresh records: " + getExceptionInfo());
    }
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

/** Called when a setting in the settings panel was changed.
*/
void OnSettingsChanged() {
    // if (currMapStatus == MapStatus::NotUploaded && S_AutoUpload) {
    //     startnew(WaitForCheckAndAutoUploadIfNotUploaded);
    // }
}
