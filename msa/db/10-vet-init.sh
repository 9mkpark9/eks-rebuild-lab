# 공식 MySQL 이미지의 초기화 단계에서 source 로 읽힌다 (실행 권한 없음 = source).
# 데이터 폴더가 비어 있을 때 한 번만 돈다. 할 일은 vet-provision 에 있다:
#   스키마 → 오늘 기준 시드 → 서비스별 스키마·뷰 → 서비스 계정과 권한
. /usr/local/bin/vet-provision
