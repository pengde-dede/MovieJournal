# MovieJournal · 감상 기록

[简体中文](README.md) · [English](README.en.md) · [日本語](README.ja.md) · **한국어**

감상한 영화와 TV 시리즈를 포스터, 평점, 짧은 감상평과 함께 기록하세요.

MovieJournal은 SwiftUI와 SwiftData로 개발한 macOS 네이티브 앱입니다. macOS 14 이상을 지원하며, 시스템 프레임워크를 사용하고 감상 기록을 Mac에 저장합니다.

## 1.2.1 업데이트

- 라이브러리의 “… → 排序” 메뉴에 제목 A → Z / Z → A와 공개 연도 최신순 / 오래된순을 추가했습니다. 중국어 제목은 병음 기준으로, 숫자는 자연 순서로 정렬합니다.
- 현재 공개 정보는 연도 단위입니다. 같은 연도는 제목순으로, 연도 미상 작품은 항상 마지막에 표시합니다. 검색, 유형, 시청 상태 필터와 함께 사용할 수 있으며 선택한 정렬을 기억합니다.

## 1.2.0 업데이트

- “想看”(보고 싶어요), “在看”(시청 중), “已看”(시청 완료) 상태를 지원합니다. 상태별로 필터링하고 상세 화면이나 포스터의 오른쪽 클릭 메뉴에서 변경할 수 있습니다. 새 작품의 기본 상태는 “보고 싶어요”입니다.
- 개인 평점, 감상 날짜, TV 시즌은 선택 사항이며 나중에 입력할 수 있습니다. 미평가 작품은 0점으로 취급하지 않으며 평점 정렬 시 마지막에 표시합니다.
- 상태를 변경해도 기존 평점, 감상평, 감상 이력은 유지됩니다. “시청 완료”로 변경할 때 날짜가 비어 있으면 오늘 날짜를 설정하며 편집 화면에서 지울 수 있습니다.
- 기존 기록은 데이터를 유지한 채 “시청 완료”로 이전됩니다. 이전 전에 Backups/BeforeV3.store를 생성합니다. JSON 백업은 버전 2를 사용하며 이전 버전 가져오기도 지원합니다.

## 1.1.1 업데이트

- 상세 화면의 “记录重看”(다시 감상 기록)에서 감상할 때마다 날짜, 평점, 감상평, 시즌을 저장합니다. 라이브러리에는 최근 감상 정보를 표시합니다.
- “…” 메뉴에서 정렬과 백업·복원을 사용할 수 있습니다. JSON에 작품 정보, 이력, 캐시된 포스터를 저장하고 복원 전에 추가 건수를 확인합니다. 중복 작품은 기존 로컬 데이터를 유지합니다.
- 작성한 초안을 보호하고 저장 버튼을 하단에 고정했습니다. 감독의 작품을 검색하거나 라이브러리에서 제목, 감독, 크리에이터, 출연진으로 검색할 수 있습니다.
- 설정에서 유리 효과 끄기·투명·표준과 색조 강도를 선택합니다. macOS 26 이상은 Liquid Glass를, 이전 OS는 대체 머티리얼을 사용합니다. 시스템의 투명도 감소 설정을 반영합니다.
- V1에서 V2로 이전하기 전에 라이브러리의 Backups/BeforeV2.store에 데이터베이스 스냅샷을 저장합니다.

## 주요 기능

- **포스터 라이브러리** — 추가 날짜, 감상 날짜, 개인 평점, 제목, 공개 연도로 정렬합니다. 제목, 감독, 크리에이터, 출연진으로 검색하고 영화／TV 시리즈를 필터링할 수 있습니다.
- **온라인 검색** — TMDB에서 작품을 선택하면 제목, 공개 연도, 장르, 감독 또는 크리에이터, 주요 출연진 5명, 줄거리, 포스터, TMDB 평점을 가져옵니다.
- **개인 감상 기록** — 시청 상태를 관리하고 날짜, 1~10 정수 평점, 감상평, 시즌을 선택적으로 저장합니다.
- **추가 평점** — 선택 사항인 OMDb API 키를 설정하면 작품을 추가할 때 IMDb와 Rotten Tomatoes 평점을 가져옵니다.
- **오프라인 조회와 편집** — 저장한 작품 정보와 다운로드한 포스터를 보고, 개인 감상 정보를 오프라인으로 수정할 수 있습니다.
- **중복 확인과 삭제 확인** — 같은 작품을 추가하면 기존 기록을 열 수 있습니다. 삭제 전 확인을 거치고, 남아 있는 기록의 참조에 따라 포스터를 정리합니다.
- **키체인 저장** — 설정에서 API 키를 저장, 검증, 변경하거나 삭제할 수 있습니다.

## 시작하기

1. 저장소를 복제하고 Xcode에서 프로젝트를 엽니다.

   ```sh
   git clone https://github.com/pengde-dede/MovieJournal.git
   cd MovieJournal
   open MovieJournal.xcodeproj
   ```

2. 이 버전은 Xcode 27.2에서 빌드를 검증했으며 macOS 14 이상을 대상으로 합니다. 컴파일에는 Liquid Glass API를 포함한 macOS SDK가 필요합니다.
3. **Signing & Capabilities**에서 **Automatically manage signing**을 켜고 앱과 테스트 타깃에 본인의 개발 팀을 지정합니다.
4. scheme은 **MovieJournal**, 실행 대상은 **My Mac**으로 선택하고 **⌘R**을 누릅니다.
5. **⌘,**로 설정을 열고 **TMDB API Key(v3)**를 입력해 저장한 뒤 **验证**(검증)를 클릭합니다. API Key(v3 auth)를 사용하세요. 긴 Read Access Token을 입력하면 형식 안내가 표시됩니다.
6. 추가 평점이 필요하면 활성화된 **OMDb API 키**도 입력합니다. 키는 각 공식 페이지에서 발급받을 수 있습니다. [TMDB API 설정](https://www.themoviedb.org/settings/api) · [OMDb API 키](https://www.omdbapi.com/apikey.aspx)

## 작품 기록하기

**添加观影记录**(감상 기록 추가)에서 작품을 검색한 뒤 바로 “想看”(보고 싶어요)에 저장할 수 있습니다. “在看”(시청 중)이나 “已看”(시청 완료)도 선택할 수 있습니다. 평점, 날짜, 감상평, 시즌은 나중에 입력해도 됩니다. 입력할 경우 평점은 1~10의 정수, 시즌은 2와 같은 양의 정수를 사용하세요.

개인 정보 입력을 마치면 바로 저장할 수 있습니다. 포스터는 라이브러리에서 계속 캐시하며 다운로드 실패 시 다시 시도할 수 있습니다. OMDb를 설정하지 않았거나 평점이 없거나 요청이 실패하면 추가 평점이 비어 있을 수 있습니다. 상세 화면에서 IMDb와 Rotten Tomatoes 평점을 수동으로 새로 고칠 수 있습니다.

저장하면 상세 화면이 열리며 개인 정보를 수정하거나 확인 후 기록을 삭제할 수 있습니다. 메인 화면의 검색은 저장된 작품을 찾는 데 사용하고, 새 작품은 추가 화면에서 검색합니다.

## 데이터와 현재 지원 범위

| 항목 | 동작 |
| --- | --- |
| 작품 식별 | 미디어 유형과 TMDB ID로 식별하며 한 작품에 여러 감상 이력을 저장 |
| 날짜와 평점 | 모두 선택 사항. “시청 완료”로 변경할 때 날짜가 비어 있으면 오늘로 설정하며 편집 화면에서 삭제 가능. 평점 입력 시 1~10의 정수 사용 |
| 검색 결과 | 온라인 검색은 첫 번째 결과 페이지를 표시 |
| 작품 정보 | 중국어를 우선 사용하며 중국어 줄거리가 비어 있으면 영어로 가져오고 언어를 표시 |
| 외부 서비스 평점 | 로컬 스냅샷으로 저장하며 OMDb 평점은 제공되지 않을 수 있음 |
| 데이터베이스 | 앱 샌드박스의 `Application Support/MovieJournal/MovieJournal.store`에 V3 스키마로 저장 |
| 포스터 | 저장된 작품은 같은 디렉터리의 `Posters/`에 저장하고 검색 썸네일은 메모리에 캐시 |
| 오프라인 사용 | 저장된 정보와 캐시된 포스터 조회, 기록 편집 및 삭제 가능 |
| 동기화와 키 | 데이터는 로컬에 저장하며 CloudKit 동기화는 꺼져 있음. API 키는 macOS 키체인에 저장하며 iCloud 키체인 동기화는 꺼져 있음 |

앱 화면은 현재 중국어로 제공됩니다. 페이지 상단의 언어 링크로 README 문서의 언어를 전환할 수 있습니다.

## 빌드와 테스트

프로젝트 루트에서 빌드와 일반 테스트를 실행하거나 Xcode에서 **⌘U**를 누릅니다.

```sh
xcodebuild -project MovieJournal.xcodeproj -scheme MovieJournal -configuration Debug -destination 'platform=macOS' build
xcodebuild -project MovieJournal.xcodeproj -scheme MovieJournal -configuration Debug -destination 'platform=macOS' test
```

일반 테스트는 모의 네트워크 응답, 테스트용 키, 독립적인 임시 데이터베이스를 사용합니다. 선택 사항인 실제 TMDB API 검증은 명시적으로 활성화해야 하며, Mac에 저장된 TMDB 키를 읽어 API 요청을 보냅니다.

```sh
TEST_RUNNER_MOVIEJOURNAL_LIVE_API_TESTS=1 xcodebuild -project MovieJournal.xcodeproj -scheme MovieJournal -configuration Debug -destination 'platform=macOS' -only-testing:MovieJournalTests/LiveAPISmokeTests test
```

실제 API 테스트는 임시 데이터베이스에서 검색, 작품 정보 조회, 포스터 캐시, 오프라인 편집 및 삭제를 검증합니다. 클릭, 키보드 입력, 창 닫기, 오프라인 재시작의 수동 확인 절차는 개발 기록에 있습니다.

## 프로젝트 구조

| 경로 | 역할 |
| --- | --- |
| `MovieJournal/App/` | 앱 진입점 |
| `MovieJournal/Models/` | 버전 관리 스키마, 작품 정보, 감상 정보 초안, 마이그레이션 계획 |
| `MovieJournal/Persistence/` | 로컬 컨테이너, 조회, 명시적 저장, 중복 확인, 롤백 |
| `MovieJournal/Networking/` | TMDB / OMDb 요청, 파싱, 오류 처리 |
| `MovieJournal/Services/` | 키체인, 키 검증, 작품 정보 조회, 포스터 캐시와 정리 |
| `MovieJournal/ViewModels/` | 추가, 편집, 삭제, 설정, 라이브러리 상태 관리 |
| `MovieJournal/Views/` | SwiftUI 화면과 공통 컴포넌트 |
| `MovieJournalTests/` | Swift Testing 테스트와 선택적 실제 API 검증 |

## 개발 기록

기존 README의 단계별 인수 확인 절차, 과거 테스트 결과, 버그 수정, 서명 설정, 저장 방식 설명을 전문 그대로 보존했습니다. 과거 검증 결과는 기록에 명시된 버전과 날짜에 해당합니다. [전체 개발 기록(중국어)](docs/DEVELOPMENT.zh-CN.md)

## 데이터 출처와 감사의 말

작품 정보와 포스터는 TMDB에서, IMDb와 Rotten Tomatoes의 추가 평점은 OMDb에서 제공합니다. [TMDB API](https://developer.themoviedb.org/reference/intro/getting-started) · [OMDb API](https://www.omdbapi.com/)

This product uses the TMDB API but is not endorsed or certified by TMDB.
