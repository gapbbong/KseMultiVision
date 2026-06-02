$path = "index.html"
$html = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)

# 줄바꿈 형식을 LF(\n)로 통일
$html = $html -replace "`r`n", "`n"

function to-lf($str) {
    return $str -replace "`r`n", "`n"
}

# 1. Zone B CSS 변경 (작은따옴표 Here-string으로 변경)
$oldZoneB = to-lf @'
    /* 구역 B: 1사분면 가운데 가로 미디어 (50vh 전체 높이 복구) */
    .zone-b {
      position: absolute; left: 28.125vh; top: 0;
      width: 88.89vh; height: 50vh;
      border-right: 2px solid rgba(0, 187, 249, 0.3);
      background: #020617; z-index: 4; overflow: hidden;
      transition: width 0.4s cubic-bezier(0.16, 1, 0.3, 1);
    }
'@

$newZoneB = to-lf @'
    /* 구역 B: 1사분면 우측 가로 미디어 (1사분면 오른쪽 끝인 50vw까지 확장) */
    .zone-b {
      position: absolute; left: 28.125vh; top: 0;
      width: calc(50vw - 28.125vh); height: 50vh;
      border-right: 2px solid rgba(0, 187, 249, 0.3);
      background: #020617; z-index: 4; overflow: hidden;
    }
'@

if ($html.Contains($oldZoneB)) {
    $html = $html.Replace($oldZoneB, $newZoneB)
    Write-Host "Success replacing Zone B CSS"
} else {
    Write-Warning "Could not find Zone B CSS block"
}

# 2. Zone F CSS 변경
$oldZoneF = to-lf @'
    /* 구역 F: 1사분면 좌측 상단 학습동기 부여 명언 영역 (미디어 위에 투명 오버레이로 얹음) */
    .zone-f {
      position: absolute; left: 0; top: 0;
      width: 117.015vh; height: 10vh;
      background: linear-gradient(to bottom, rgba(2, 6, 23, 0.85) 0%, rgba(2, 6, 23, 0.3) 70%, rgba(2, 6, 23, 0) 100%);
      z-index: 10;
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      padding: 6px 20px;
      overflow: hidden;
      box-sizing: border-box;
      box-shadow: none;
      animation: breathingGlowText 5s ease-in-out infinite alternate;
      transition: width 0.4s cubic-bezier(0.16, 1, 0.3, 1);
    }
'@

$newZoneF = to-lf @'
    /* 구역 F: 1사분면 좌측 상단 학습동기 부여 명언 영역 (미디어 위에 투명 오버레이로 얹음) */
    .zone-f {
      position: absolute; left: 0; top: 0;
      width: 50vw; height: 10vh;
      background: linear-gradient(to bottom, rgba(2, 6, 23, 0.85) 0%, rgba(2, 6, 23, 0.3) 70%, rgba(2, 6, 23, 0) 100%);
      z-index: 10;
      display: flex;
      flex-direction: column;
      justify-content: center;
      align-items: center;
      padding: 6px 20px;
      overflow: hidden;
      box-sizing: border-box;
      box-shadow: none;
      animation: breathingGlowText 5s ease-in-out infinite alternate;
    }
'@

if ($html.Contains($oldZoneF)) {
    $html = $html.Replace($oldZoneF, $newZoneF)
    Write-Host "Success replacing Zone F CSS"
} else {
    Write-Warning "Could not find Zone F CSS block"
}

# 3. Zone E CSS 제거
$oldZoneECss = to-lf @'
    /* 구역 E: 1사분면 우측 급식/날씨 인포그래픽 */
    .zone-e {
      position: absolute; left: 93.61vh; top: 0;
      width: calc(50vw - 93.61vh); height: 50vh;
      background: linear-gradient(135deg, rgba(13,27,42,0.95) 0%, rgba(2,6,23,0.95) 100%);
      border-right: 2px solid rgba(254, 228, 64, 0.25);
      padding: 16px; z-index: 4;
      display: flex; flex-direction: column; gap: 10px; overflow: hidden;
      transition: left 0.4s cubic-bezier(0.16, 1, 0.3, 1), width 0.4s cubic-bezier(0.16, 1, 0.3, 1);
    }
'@

if ($html.Contains($oldZoneECss)) {
    $html = $html.Replace($oldZoneECss, "")
    Write-Host "Success removing Zone E CSS"
} else {
    Write-Warning "Could not find Zone E CSS block"
}

# 4. JS updateFlexibleLayout 정의부 및 resize 리스너 제거
$oldFlexDefAndResize = to-lf @'
    // ========================================================
    // 동적 가변 레이아웃 조절 함수 (Zone B 비율 연동)
    // ========================================================
    function updateFlexibleLayout(item) {
      if (!item || item.isVertical) return;
      
      const vh = window.innerHeight / 100;
      const vw = window.innerWidth / 100;
      const height = 50 * vh; // 50vh 고정
      
      const ratio = item.ratio || (16/9);
      let zoneBWidth = height * ratio;
      
      const zoneAWidth = 28.125 * vh;
      const minZoneEWidth = 30 * vh; // Zone E 최소 너비 보장
      const maxZoneBWidth = (50 * vw) - zoneAWidth - minZoneEWidth;
      
      if (zoneBWidth > maxZoneBWidth) {
        zoneBWidth = maxZoneBWidth;
      }
      if (zoneBWidth < 30 * vh) {
        zoneBWidth = 30 * vh; // 최소 너비 보장
      }
      
      // Zone B 가로폭 업데이트
      const zoneBEl = document.querySelector('.zone-b');
      if (zoneBEl) {
        zoneBEl.style.width = `${zoneBWidth}px`;
      }
      
      // Zone E 시작 좌표 및 너비 연동
      const zoneEEl = document.querySelector('.zone-e');
      if (zoneEEl) {
        const zoneELeft = zoneAWidth + zoneBWidth;
        zoneEEl.style.left = `${zoneELeft}px`;
        zoneEEl.style.width = `calc(50vw - ${zoneELeft}px)`;
      }
      
      // Zone F 명언 오버레이 배너 너비 동기화 (Zone A + Zone B 전체 덮음)
      const zoneFEl = document.querySelector('.zone-f');
      if (zoneFEl) {
        const zoneFWidth = zoneAWidth + zoneBWidth;
        zoneFEl.style.width = `${zoneFWidth}px`;
      }
    }

    // 창 크기 변경 시 레이아웃 자동 보정 리스너
    window.addEventListener('resize', () => {
      const container = document.getElementById('horizontal-container');
      if (!container || !horizontalList || horizontalList.length === 0) return;
      const items = container.querySelectorAll('.hmedia-item');
      let activeIdx = 0;
      for (let i = 0; i < items.length; i++) {
        if (items[i].classList.contains('active')) {
          activeIdx = i;
          break;
        }
      }
      if (horizontalList[activeIdx]) {
        updateFlexibleLayout(horizontalList[activeIdx]);
      }
    });
'@

if ($html.Contains($oldFlexDefAndResize)) {
    $html = $html.Replace($oldFlexDefAndResize, "")
    Write-Host "Success removing JS updateFlexibleLayout block"
} else {
    Write-Warning "Could not find JS updateFlexibleLayout block"
}

# 5. JS 호출부 제거
$oldCall1 = to-lf @'
      // 최초 가로폭 레이아웃 동적 갱신
      if (typeClass === 'hmedia') {
        updateFlexibleLayout(list[0]);
      }
'@

$oldCall2 = to-lf @'
        // 슬라이드 변경 시 레이아웃 동적 가변 조절 연동
        if (typeClass === 'hmedia') {
          updateFlexibleLayout(list[idx]);
        }
'@

$html = $html.Replace($oldCall1, "").Replace($oldCall2, "")

# 6. 오늘의 급식 패널을 급식/날씨 번갈아 노출되는 대시보드 패널로 교체
$oldMealCol = to-lf @'
        <!-- 오늘의 웰빙 급식 패널 (기존 Zone E에서 2사분면 Zone C로 이동) -->
        <div style="display: flex; flex-direction: column; gap: 10px; justify-content: flex-start; overflow-y: auto; padding-right: 4px; box-sizing: border-box;">
          <div id="meal-card-header" class="section-title">
            <i class="fa-solid fa-salad"></i> <span id="meal-card-title">오늘의 웰빙 급식</span>
          </div>
          <div id="meal-card-content" class="infographic-meal" style="display: flex; flex-direction: column; gap: 8px; flex-grow: 1; justify-content: flex-start;">
            <div class="meal-meta-row" style="padding: 8px 12px;">
              <div class="calories-radial-box">
                <div class="calories-icon-wrap" style="width: 32px; height: 32px; font-size: 0.9rem;">
                  <i class="fa-solid fa-fire-flame-curved"></i>
                </div>
                <div class="calories-data">
                  <span class="calories-title" style="font-size: 0.65rem;">총 열량</span>
                  <span class="calories-value" id="meal-cal" style="font-size: 1.0rem;">--- kcal</span>
                </div>
              </div>
              <span class="meal-date-badge" id="meal-date" style="padding: 2px 8px; font-size: 0.7rem;">---</span>
            </div>
            <div class="meal-grid" id="meal-grid-box" style="gap: 5px;">
              <div style="grid-column: span 2; text-align: center; color: var(--color-text-secondary); font-size: 0.8rem;">
                <i class="fa-solid fa-spinner fa-spin"></i> 식단 데이터를 가져오는 중...
              </div>
            </div>
          </div>
        </div>
'@

$newMealCol = to-lf @'
        <!-- 오늘의 웰빙 급식 / 내일의 기상 예보 패널 (기존 Zone E에서 2사분면 Zone C로 이동) -->
        <div style="display: flex; flex-direction: column; gap: 10px; justify-content: flex-start; overflow-y: auto; padding-right: 4px; box-sizing: border-box;">
          <!-- 오늘의 웰빙 급식 카드 -->
          <div id="meal-card-header" class="section-title">
            <i class="fa-solid fa-salad"></i> <span id="meal-card-title">오늘의 웰빙 급식</span>
          </div>
          <div id="meal-card-content" class="infographic-meal" style="display: flex; flex-direction: column; gap: 8px; flex-grow: 1; justify-content: flex-start;">
            <div class="meal-meta-row" style="padding: 8px 12px;">
              <div class="calories-radial-box">
                <div class="calories-icon-wrap" style="width: 32px; height: 32px; font-size: 0.9rem;">
                  <i class="fa-solid fa-fire-flame-curved"></i>
                </div>
                <div class="calories-data">
                  <span class="calories-title" style="font-size: 0.65rem;">총 열량</span>
                  <span class="calories-value" id="meal-cal" style="font-size: 1.0rem;">--- kcal</span>
                </div>
              </div>
              <span class="meal-date-badge" id="meal-date" style="padding: 2px 8px; font-size: 0.7rem;">---</span>
            </div>
            <div class="meal-grid" id="meal-grid-box" style="gap: 5px;">
              <div style="grid-column: span 2; text-align: center; color: var(--color-text-secondary); font-size: 0.8rem;">
                <i class="fa-solid fa-spinner fa-spin"></i> 식단 데이터를 가져오는 중...
              </div>
            </div>
          </div>

          <!-- 기상 예보 카드 (13:20 교대 분기 연동) -->
          <div id="weather-card-header" class="section-title" style="border-bottom: 1px solid rgba(0,187,249,0.15); color: var(--color-zone-b); display: none;">
            <i class="fa-solid fa-cloud-sun" style="text-shadow: 0 0 10px rgba(0,187,249,0.4);"></i>
            <span id="weather-card-title">내일의 기상 예보</span>
          </div>
          <div id="weather-card-content" class="infographic-weather" style="display: none; flex-direction: column; gap: 8px; flex-grow: 1; justify-content: center;">
            <!-- 날씨 그래픽 + 기온 메인 행 -->
            <div style="display: flex; align-items: center; gap: 14px; background: rgba(255,255,255,0.02); border: 1px solid rgba(255,255,255,0.05); border-radius: 12px; padding: 10px 14px;">
              <div class="weather-graphic-wrap" id="weather-graphic">
                <div class="wx-cloudsun">
                  <div class="wx-sun-small"></div>
                  <div class="wx-cloud-small"></div>
                </div>
              </div>
              <div style="display: flex; flex-direction: column; gap: 2px; flex: 1;">
                <span style="font-size: 0.65rem; color: var(--color-text-secondary); font-weight: 700; text-transform: uppercase; letter-spacing: 1px;">기온 (최저/최고)</span>
                <span id="weather-temp" style="font-family: var(--font-outfit); font-size: 1.2rem; font-weight: 800; color: #ffffff;">--.-°C / --.-°C</span>
                <span id="weather-status" style="font-size: 0.75rem; font-weight: 800; color: var(--color-zone-b); margin-top: 2px;">맑음</span>
              </div>
              <div style="display: flex; flex-direction: column; align-items: flex-end; gap: 2px; margin-left: auto;">
                <span style="font-size: 0.6rem; color: var(--color-text-muted); font-weight: 600;">체감 최고</span>
                <span id="weather-apparent" style="font-family: var(--font-outfit); font-size: 0.9rem; font-weight: 800; color: var(--color-text-secondary);">--.-°C</span>
              </div>
            </div>
            <!-- 상세 지표 그리드 -->
            <div class="weather-grid" style="gap: 5px;">
              <div class="weather-grid-item" style="color: var(--color-text-primary); display: flex; justify-content: space-between; align-items: center; padding: 6px 10px;">
                <div style="display: flex; align-items: center; gap: 6px;">
                  <i class="fa-solid fa-droplet" style="color: #38bdf8; font-size: 0.8rem;"></i>
                  <span style="font-size: 0.75rem;">강수 확률</span>
                </div>
                <span id="weather-humidity" style="font-family: var(--font-outfit); color: #ffffff; font-size: 0.8rem;">--%</span>
              </div>
              <div class="weather-grid-item" style="color: var(--color-text-primary); display: flex; justify-content: space-between; align-items: center; padding: 6px 10px;">
                <div style="display: flex; align-items: center; gap: 6px;">
                  <i class="fa-solid fa-wind" style="color: #94a3b8; font-size: 0.8rem;"></i>
                  <span style="font-size: 0.75rem;">최대 풍속</span>
                </div>
                <span id="weather-wind" style="font-family: var(--font-outfit); color: #ffffff; font-size: 0.8rem;">-- m/s</span>
              </div>
              <div class="weather-grid-item" style="color: var(--color-text-primary); display: flex; justify-content: space-between; align-items: center; padding: 6px 10px;">
                <div style="display: flex; align-items: center; gap: 6px;">
                  <i class="fa-solid fa-smog" style="color: #fbbf24; font-size: 0.8rem;"></i>
                  <span style="font-size: 0.75rem;">미세먼지</span>
                </div>
                <span id="weather-pm10" style="font-family: var(--font-noto); color: #ffffff; font-size: 0.8rem;">좋음</span>
              </div>
              <div class="weather-grid-item" style="color: var(--color-text-primary); display: flex; justify-content: space-between; align-items: center; padding: 6px 10px;">
                <div style="display: flex; align-items: center; gap: 6px;">
                  <i class="fa-solid fa-location-dot" style="color: #00bbf9; font-size: 0.8rem;"></i>
                  <span style="font-size: 0.75rem;">위치</span>
                </div>
                <span style="font-family: var(--font-noto); color: #ffffff; font-size: 0.75rem;">부산 서구</span>
              </div>
            </div>
          </div>
        </div>
"@

if ($html.Contains($oldMealCol)) {
    $html = $html.Replace($oldMealCol, $newMealCol)
    Write-Host "Success replacing Zone C Meal column"
} else {
    Write-Warning "Could not find Zone C Meal column!"
}

# 7. HTML 바디의 구역 E (중복 블록 포함 전체 영역) 제거
$lines = $html -split "\n"
$startIdx = -1
$endIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "<!-- \[구역 E:") {
        $startIdx = $i
        break
    }
}
for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    if ($lines[$i] -match "</div><!-- /zone-e -->") {
        $endIdx = $i
        break
    }
}

if ($startIdx -ne -1 -and $endIdx -ne -1 -and $endIdx -ge $startIdx) {
    $newLines = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -lt $startIdx -or $i -gt $endIdx) {
            $newLines += $lines[$i]
        }
    }
    $lines = $newLines
    Write-Host "Success removing HTML Zone E blocks (from line $startIdx to $endIdx)"
} else {
    Write-Warning "Could not find Zone E HTML block!"
}

[System.IO.File]::WriteAllLines($path, $lines, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Layout adjustment script completed!"
