## 2026-11-07 추가 변경 (빌드 12)

- 공유 식탁 참여 순서로 사진 자리를 고정합니다. 한 명만 올렸을 때도 빈자리를 남기며, 같은 사람이 여러 장 올리면 같은 열에 쌓입니다.
- 좋아요/맛있겠다 반응도 원본 사진 작성자의 동의에 따라 알립니다. 반응 취소에는 알림을 보내지 않으며 재클릭으로 같은 알림을 반복하지 않습니다.
- 새 사진·좋아요·댓글은 설정에서 각각 켭니다. 발송자/수신자 모두 새 버전이 필요합니다.
- 기기 식탁 삭제와 공유 식탁 나가기를 추가했습니다. 기기 식탁을 삭제하면 그 식탁에서만 보관한 사진도 삭제합니다. 공유 식탁의 다른 멤버 기록은 유지합니다.
- iOS 17 이상 홈 화면에 ‘한 끼 바로 촬영’ 위젯을 추가할 수 있습니다. 카메라는 앱에서 열리며, 촬영 후 오른쪽 위 ‘올리기’를 눌러 전송합니다. 첫 사용 시 카메라 권한과 식탁이 필요합니다.
- 사진의 EXIF 촬영 시각을 우선 사용하고, 새 촬영에서 메타데이터가 없으면 카메라에서 돌아온 시각을 씁니다. 05:00~10:00 아침, 11:00~16:00 점심, 17:00~22:00 저녁(끝 분 포함)이며 그 외에는 직접 선택합니다. JPEG 외 기존 사진에서 시각을 읽을 수 없으면 선택한 식사를 유지합니다.
- 검증: Flutter 29개, 서버 12개, Firestore 규칙 64개 검사 통과. 앱/테스트 분석 통과. WidgetKit 및 AppDelegate/SceneDelegate Swift 타입 검사 통과. 서명된 새 빌드와 실제 홈 화면 위젯/두 iPhone 푸시 수신은 미검증입니다.
- 운영 배포는 아직 완료하지 않았습니다. Cloudflare OAuth 승인 콜백이 없고, Firebase CLI 자동 배포는 메타데이터 자격 증명 탐색으로 자동 보안 검토에서 차단되었습니다. 명시적인 Firebase 계정 인증 후 Firestore 규칙, Cloudflare Worker 순서로 배포해야 합니다.

# 알림 종류별 수신 설정 — 새 코드, 운영 배포 필요

이번 변경은 아직 운영 서버에 배포하지 않았습니다. 아래 과거 운영 기록은 기존 밥 안부 알림에만 해당합니다.

- **밥 안부 알림**: 기존 종 버튼의 식사 알림입니다. 기존 동의 상태를 유지합니다.
- **새 사진 알림**: 같은 식탁의 다른 멤버가 사진을 올리면 받습니다. 기본값은 꺼짐입니다.
- **내 사진의 댓글 알림**: 내 사진에 다른 멤버가 댓글을 달면 받습니다. 기본값은 꺼짐입니다.
- 세 가지를 독립적으로 설정하며 마지막 종류를 끄면 기기 등록을 해제합니다. iOS 알림 권한이 필요합니다. Android 푸시 수신은 이번 변경에 포함되지 않습니다.

## 변경 배포 순서

1. `server/nudges`에서 `npm ci && npm test && npm run deploy`를 실행합니다. 기존 Cloudflare 계정 인증과 APNs 비밀 설정을 그대로 사용합니다. Firestore 규칙 변경이나 Firebase 유료 전환은 필요 없습니다.
2. 갱신된 앱을 빌드해 두 iPhone에 설치합니다. 사진/댓글을 올리는 쪽도 새 빌드여야 합니다.
3. 양쪽 모두 공유 식탁에 참여하고 원하는 알림 종류를 켭니다. 상대 사진 업로드, 내 사진에 상대 댓글, 내 사진 업로드/내 댓글(알림 없음), 각각 끄기, 중복 요청을 확인합니다.

새 `/activity` 경로는 로그인 토큰과 현재 식탁 멤버 여부를 검증하고 실제 Firestore 사진/댓글을 읽어 작성자와 생성 시각을 확인합니다. 본인에게는 발송하지 않으며 댓글은 원본 사진 작성자에게만 보냅니다. 임의 수신자/문구는 받지 않습니다. 알림에 사진이나 댓글 본문을 포함하지 않습니다.

업로드와 댓글 저장이 완료된 후 앱의 로컬 발송 대기열에 이벤트를 보관합니다. 전송 실패 시 앱 복귀/재실행 때 재시도하며, 24시간이 지난 이벤트는 버립니다. 서버는 이벤트별로 48시간 중복을 막습니다. 앱이 저장 직후 종료되거나 장기간 다시 실행되지 않는 경우 발송이 누락될 수 있습니다. 무료 구성을 유지하기 위해 상시 Firestore 트리거 대신 작성 앱이 알림 서버에 전달합니다.

2026-11-07 검증: Node 서버 테스트 11개, Flutter 기존 테스트 19개와 새 알림 테스트 5개 통과. 변경한 앱 코드와 새 테스트 분석 이상 없음. 운영 배포 자격 증명은 Cloudflare 오류 9109(Invalid access token)로 거절되어 갱신이 필요합니다. 새 iOS 빌드 및 두 실기기 수신은 아직 수행하지 않았습니다.

---

# 밥 안부 푸시 알림 — 서버 연결 완료

식사별 종 버튼을 누르면 같은 식탁에서 알림을 켠 다른 사람에게 `아침 뭐 먹어!?`, `점심 뭐 먹어!?`, `저녁 뭐 먹어!?`를 보냅니다. 같은 식탁/식사에는 30분 제한을 적용합니다. 빌드 10에 운영 서버 주소가 기본 설정되어 있습니다. 실제 iPhone 두 기기 수신 확인은 아직 하지 않았습니다.

2026-10-21 설정 상태: 앱 한 개에 제한된 production APNs 키를 생성했고 Cloudflare `mwomeogeo-nudges`의 Production 비밀 설정 3개에 암호화해 저장했습니다. Apple App ID의 Push Notifications도 활성화했습니다. `https://mwomeogeo-nudges.islaay.workers.dev`에 알림 코드와 SQLite Durable Object를 배포했고 버전 `86542357-6b87-42ed-bd1e-105abd5f7ca6`이 운영 트래픽 100%를 처리합니다. 인증 없음·위조 인증·실제 익명 인증의 비멤버 요청 차단을 포함한 운영 검사 5개를 통과했습니다. 검사 중 생성한 임시 익명 계정은 삭제했고 식탁이나 실제 푸시는 만들지 않았습니다.

이 배포에는 해당 Worker 하나의 Editor 권한만 가진 임시 토큰을 사용했습니다. 처음 `wrangler deploy`는 코드·저장소 업로드 이후 계정 전체의 서브도메인 조회 권한이 없어 종료 오류를 냈습니다. 기존 운영 도메인은 유지되었고, 이후 코드는 `wrangler versions upload`와 `wrangler versions deploy VERSION_ID@100% --yes`로 업로드·활성화했습니다. 계정 전체 권한을 추가하지 않았습니다. 서버 로그 영구 저장은 비활성 상태입니다.

## 처음 한 번 연결

1. Apple Developer의 `com.chaen.mwomeogeo` App ID에서 Push Notifications를 켭니다. Xcode 자동 서명으로 새 프로비저닝 프로필을 받습니다.
2. Apple Developer에서 해당 앱의 **production APNs** 전송이 가능한 `.p8` 키와 Key ID, Team ID를 준비합니다. 키는 로컬 보안 폴더에 보관하고 Git/Flutter/대화창에 넣지 않습니다. 키 권한은 이 앱에 필요한 범위로 제한합니다.
3. Cloudflare **Workers Free** 계정으로 로그인한 뒤 다음을 실행합니다. Firebase Spark 요금제를 바꾸지 않습니다. SQLite Durable Objects의 Free 한도 내에서 사용하며 한도 초과 시 요금제를 자동 변경하지 않습니다.

```sh
cd server/nudges
npm ci
npx wrangler login
npx wrangler deploy
npx wrangler secret put APNS_PRIVATE_KEY
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APNS_TEAM_ID
```

`APNS_PRIVATE_KEY`에는 `.p8` 파일의 전체 PEM 내용을 안전한 입력창에서 입력합니다. 나머지는 Apple의 해당 Key ID/Team ID입니다. 개인 키나 Firebase 관리자 키를 앱에 포함하지 않습니다.

4. 앱을 빌드합니다. 운영 주소는 기본 설정되어 있고 공개 설정이므로 개인 키가 아닙니다. 별도 환경이 필요할 때만 `--dart-define=NUDGE_API_URL=https://별도주소.workers.dev`로 바꿉니다.

```sh
flutter pub get
flutter build ipa --build-number=10
open build/ios/archive/Runner.xcarchive
```

5. 두 iPhone에 새 빌드를 설치하고 **내 정보 → 식사 알림 받기**를 켭니다. 같은 식탁에 참여한 뒤, 상대 기기를 잠근 상태에서 식사 옆 종 버튼으로 확인합니다. 권한 거절 시 iPhone 설정에서 앱 알림을 다시 허용할 수 있습니다. 앱이 열려 있어도 배너를 표시하며 알림을 누르면 멤버 권한이 있는 식탁의 오늘 피드를 선택합니다.

TestFlight/App Store는 production APNs를 사용합니다. Debug는 sandbox를 사용하므로 디버그 실험 시 해당 환경을 허용한 키/별도 서버 설정이 필요합니다. 시뮬레이터의 실제 APNs 수신을 검증한 것으로 간주하지 않습니다. 알림 도착은 OS 알림 설정·집중 모드·연결 상태의 영향을 받습니다.

## 보안과 동작

- 클라이언트는 Firebase 익명 인증 ID 토큰으로 요청합니다. 서버는 기존 Firestore 멤버 전용 규칙을 통과한 요청만 허용합니다. JSON 토큰을 단순 디코딩한 값만으로 인증하지 않습니다.
- 수신자는 서버가 읽은 현재 멤버 목록에서 결정합니다. 요청으로 받은 임의 메시지/수신자/작성자 필드는 사용하지 않습니다.
- APNs 토큰은 비공개 Durable Object에만 보관합니다. 클라이언트에 다른 사람의 토큰을 반환하지 않습니다. 한 사용자당 현재 토큰 하나를 유지하고 토큰이 새 사용자로 등록되면 예전 소유자 연결을 제거합니다.
- 알림 끄기, 토큰 변경, APNs 만료 응답을 처리합니다. 30일 이상 갱신되지 않은 토큰에는 전송하지 않습니다. 익명 식별값은 기기/앱 데이터 초기화 시 바뀔 수 있습니다.
- 원자적 30분 제한과 요청 ID로 동시 클릭/재시도를 처리합니다. 네트워크 타임아웃으로 수락 여부가 불명확하면 자동으로 재발송하지 않습니다.
- 전송 성공은 APNs가 요청을 수락한 경우만 반환합니다. 사용자 화면에서 실제 읽음/도착을 확인한 것으로 표시하지 않습니다.
- 운영 서버에 실제 알림을 보내는 테스트는 아직 실행하지 않았습니다.

## 검증

```sh
npm test
npx wrangler deploy --dry-run
```

Node 테스트 6개는 인증/권한/입력 경계, 본인 제외/문구/중복 방지, 동시 전송 제한, 토큰 교체/끄기/소유권, APNs 거절, 업스트림 리디렉션 거부를 모의합니다. Workers가 지원하지 않는 `redirect: 'error'` 대신 `manual`을 사용하고 3xx는 인증·전송 성공으로 처리하지 않습니다. Flutter 테스트 19개와 변경 파일 분석을 통과했습니다. iOS AppDelegate는 실제 iOS SDK와 Flutter 헤더로 Swift 타입 검사를 통과했습니다. 코드 서명·실제 iPhone 빌드·두 기기 수신은 별도 확인이 필요합니다. 운영 검사 기록은 `preview/nudge-live-checks.json`에 있습니다.

공식 참고:
- https://firebase.google.com/docs/functions/get-started (Functions 배포에는 Blaze 필요)
- https://developers.cloudflare.com/durable-objects/platform/pricing/
- https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns
- https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns
