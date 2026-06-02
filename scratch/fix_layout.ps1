$lines = Get-Content -Encoding utf8 index.html
$lines[913] = @"
    <!-- [구역 A: 1사분면 좌측 세로 미디어 (50vh 전체 높이 복구)] -->
    <div class="zone-a">
      <div class="media-container" id="vertical-container">
        <!-- JS dynamically inserts vertical 9:16 media contents -->
      </div>
    </div>

    <!-- [구역 B: 1사분면 가운데 가로 미디어 (50vh 전체 높이 복구)] -->
    <div class="zone-b">
      <div class="media-container" id="horizontal-container">
        <!-- JS dynamically inserts horizontal media contents -->
      </div>
    </div>

    <!-- [구역 F: 1사분면 좌측 상단 학습동기 부여 명언 영역 (미디어 위에 투명 오버레이로 얹음)] -->
    <div class="zone-f" id="quote-zone">
      <div class="quote-container" id="quote-container">
        <div class="quote-text" id="quote-text">행동은 모든 성공의 기초가 된다.</div>
        <div class="quote-author" id="quote-author" style="display: none;">- 파블로 피카소 -</div>
      </div>
    </div>

    <!-- [구역 C: 2사분면 전체 우측 종합 대시보드] -->
"@
[System.IO.File]::WriteAllLines("index.html", $lines, (New-Object System.Text.UTF8Encoding $false))
Write-Host "index.html layout restored successfully."
