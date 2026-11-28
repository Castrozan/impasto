{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  quickshell,
  qt6,
  kdePackages,
  papirus-icon-theme,
  unicode-emoji,
  cldr-annotations,
  isocodes,
  xkeyboard_config,
  libxkbcommon,
  noto-fonts-color-emoji,
  awww,
  bluez,
  brightnessctl,
  cava,
  coreutils,
  curl,
  dbus,
  ddcutil,
  ffmpeg-headless,
  fontconfig,
  git,
  gnugrep,
  gnused,
  grim,
  gtk3,
  hyprpicker,
  hyprsunset,
  imagemagick,
  inotify-tools,
  iproute2,
  libnotify,
  mpvpaper,
  networkmanager,
  playerctl,
  procps,
  pulseaudio,
  satty,
  slurp,
  wf-recorder,
  wireplumber,
  wl-clipboard,
  xdg-utils,
  sourceRevision,
  quickshellConfigurationName ? "impasto",
}:
let
  pythonWithWallpaperCatalog = python3.withPackages (packages: [ packages.beautifulsoup4 ]);

  runtimePrograms = [
    awww
    bluez
    brightnessctl
    cava
    coreutils
    curl
    dbus
    ddcutil
    ffmpeg-headless
    fontconfig
    git
    gnugrep
    gnused
    grim
    gtk3
    hyprpicker
    hyprsunset
    imagemagick
    inotify-tools
    iproute2
    libnotify
    mpvpaper
    networkmanager
    playerctl
    procps
    pulseaudio
    pythonWithWallpaperCatalog
    quickshell
    satty
    slurp
    wf-recorder
    wireplumber
    wl-clipboard
    xdg-utils
  ];

  qmlImportPath = lib.makeSearchPath "lib/qt-6/qml" [ qt6.qtmultimedia ];
  qtPluginPath = lib.makeSearchPath "lib/qt-6/plugins" [ qt6.qtmultimedia ];
in
stdenvNoCC.mkDerivation {
  pname = "impasto-shell";
  version = "0-unstable-${sourceRevision}";

  src = lib.cleanSource ../.;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python3 ];

  dontConfigure = true;
  dontBuild = true;

  postPatch = ''
    substituteInPlace home/.config/quickshell/scripts/emoji.py \
      --replace-fail /usr/share/unicode/emoji/emoji-test.txt ${unicode-emoji}/share/unicode/emoji/emoji-test.txt \
      --replace-fail /usr/share/unicode/cldr/common/annotations ${cldr-annotations}/share/unicode/cldr/common/annotations \
      --replace-fail /usr/share/iso-codes/json/iso_3166-1.json ${isocodes}/share/iso-codes/json/iso_3166-1.json
    substituteInPlace home/.config/quickshell/scripts/compositor.py \
      --replace-fail /usr/share/X11/xkb/rules/evdev.lst ${xkeyboard_config}/share/X11/xkb/rules/evdev.lst \
      --replace-fail /usr/share/X11/xkb/rules/base.lst ${xkeyboard_config}/share/X11/xkb/rules/base.lst \
      --replace-fail /usr/include/xkbcommon/xkbcommon-keysyms.h ${libxkbcommon.dev}/include/xkbcommon/xkbcommon-keysyms.h
    substituteInPlace home/.config/quickshell/services/KeyboardService.qml \
      --replace-fail /usr/share/X11/xkb/rules/evdev.lst ${xkeyboard_config}/share/X11/xkb/rules/evdev.lst
    substituteInPlace home/.config/quickshell/services/WeatherService.qml \
      --replace-fail /usr/share/icons/breeze/applets/48 ${kdePackages.breeze-icons}/share/icons/breeze/applets/48
    substituteInPlace home/.config/quickshell/components/TrayIcon.qml \
      --replace-fail /usr/share/icons/Papirus-Dark/22x22/panel ${papirus-icon-theme}/share/icons/Papirus-Dark/22x22/panel
    substituteInPlace home/.config/quickshell/scripts/camera.py \
      --replace-fail /usr/share/fonts/noto/NotoColorEmoji.ttf ${noto-fonts-color-emoji}/share/fonts/noto/NotoColorEmoji.ttf
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/impasto $out/bin $out/libexec/impasto \
      $out/share/fonts/truetype $out/share/icons $out/share/zsh/site-functions

    cp -r home/.config/quickshell $out/share/impasto/quickshell
    cp -r home/.local/share/impasto $out/share/impasto/data
    cp -r home/.local/share/wallpapers $out/share/impasto/wallpapers
    cp home/.local/share/fonts/GrapeNuts-Regular.ttf $out/share/fonts/truetype/
    cp -r home/.local/share/icons/hicolor $out/share/icons/hicolor
    cp home/.local/share/zsh/site-functions/_impasto $out/share/zsh/site-functions/_impasto
    install -Dm644 LICENSE $out/share/licenses/impasto-shell/LICENSE

    install -Dm755 home/.local/bin/impasto $out/libexec/impasto/impasto

    makeWrapper ${quickshell}/bin/qs $out/bin/impasto-shell \
      --add-flags "--config ${quickshellConfigurationName}" \
      --set QS_CONFIG_NAME ${quickshellConfigurationName} \
      --prefix PATH : ${lib.makeBinPath runtimePrograms} \
      --prefix QML_IMPORT_PATH : ${qmlImportPath} \
      --prefix QT_PLUGIN_PATH : ${qtPluginPath}

    makeWrapper $out/libexec/impasto/impasto $out/bin/impasto \
      --set QS_CONFIG_NAME ${quickshellConfigurationName} \
      --prefix PATH : ${
        lib.makeBinPath [
          quickshell
          python3
        ]
      }

    runHook postInstall
  '';

  passthru = {
    inherit quickshellConfigurationName;
    quickshellConfigurationDirectory = "share/impasto/quickshell";
  };

  meta = {
    description = "Hyprland desktop shell on Quickshell with a dynamic island";
    homepage = "https://github.com/andreumassanet/impasto";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "impasto-shell";
  };
}
