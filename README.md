# Inc0gnito
> AI-powered Self-Healing Security Infrastructure on AWS

생성형 AI와 AWS 관리형 서비스를 활용하여 보안 이벤트를 탐지, 분석, 대응, 모니터링까지 자동화한 Self-Healing Security 시스템입니다.

---

## Background

최근 클라우드 환경에서는 자격 증명 탈취, 악성 코드 실행, C2 통신 등 다양한 보안 위협이 증가하고 있습니다.

기존 보안 운영 환경에서는 Security Hub 등의 탐지 결과를 관리자가 직접 확인하고 대응해야 하므로 다음과 같은 문제가 존재합니다.

- 오탐(False Positive)으로 인한 분석 부담
- 이벤트 간 연관관계 파악의 어려움
- 대응 지연
- 반복적인 수작업 처리

본 프로젝트는 생성형 AI를 활용하여 보안 이벤트를 분석하고, 자동 대응 프로세스를 구축함으로써 운영 효율성을 개선하는 것을 목표로 하였습니다.

---

## Architecture

<img width="1238" height="649" alt="image" src="https://github.com/user-attachments/assets/ddc0dac7-3365-45c9-82e1-7517e231481c" />


### Event Flow

1. Security Hub에서 보안 이벤트 수집
2. EventBridge를 통해 이벤트 전달
3. Lambda에서 이벤트 필터링 및 정규화
4. Amazon Bedrock 기반 AI 위험도 분석
5. Step Functions를 통한 대응 프로세스 실행
6. Systems Manager를 이용한 자동 대응
7. Slack 승인(Human-in-the-loop)
8. Grafana 기반 모니터링

---

## My Contributions

### Infrastructure

- Terraform 기반 AWS 인프라 구축
- EventBridge Rule 구성
- Lambda 배포 환경 구성

### Security Automation

- Security Hub Finding 처리 Lambda 개발
- 이벤트 필터링 및 자동 대응 트리거 로직 구현
- 보안 이벤트 정규화 및 로그 저장 구조 설계

### AI Analysis

- Amazon Bedrock 기반 AI 분석 Lambda 개발
- 위험도 평가 및 대응 전략 생성 로직 구현

### Documentation

- 프로젝트 보고서 작성
- 발표 자료 제작
- 컨퍼런스 발표

---

## Tech Stack

### Cloud

- AWS
  - Security Hub
  - GuardDuty
  - Inspector
  - Macie
  - EventBridge
  - Lambda
  - Step Functions
  - Systems Manager
  - S3
  - Amazon Bedrock
  - Amazon Managed Grafana

### Infrastructure as Code

- Terraform

### Language

- Python

### Collaboration

- Slack
- GitHub
- Notion

---

## Validation

GuardDuty Tester를 활용하여 공격 시나리오를 검증하였습니다.

### Simulation Result

- 공격 시나리오: 32개
- 보안 이벤트: 702건
- 이벤트 전달 성공률: 100%

### Performance Improvement

- 관리자 처리 이벤트: 35건 → 15건
- 처리 건수 약 57% 감소
- 평균 대응 시간: 15분 → 10분 미만
- 처리 시간 약 33% 개선

---

## Key Features

### AI-based Analysis

- 보안 이벤트 요약
- 위험도 평가
- 대응 전략 추천

### Human-in-the-loop

- Slack 승인/거부 프로세스
- 오탐 대응 안정성 확보

### Automated Response

- 인스턴스 격리
- 메모리 덤프
- AMI 생성
- 후속 모니터링

---

## Documents

- Final Report
- Conference Presentation

---

## Future Work

- 다중 클라우드(AWS, Azure, GCP) 확장
- AI 분석 정확도 향상
- 보안 서비스 추가 연동
- 자동 대응 정책 고도화
