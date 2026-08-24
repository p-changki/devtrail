#!/usr/bin/env bash
# DevTrail — 개발 자료실 분류 규칙.
#
# URL 캡처와 AI가 쓰는 분류의 이름을 한곳에 둔다. 폴더명은 언어마다 달라도
# frontmatter 값(area/topic)은 영문 slug로 고정한다. Dataview·검색·이관이
# 사용자 폴더 언어에 묶이지 않게 하기 위해서다.

_cap_tax_set() {
  CAP_TAX_TYPE="$1"; CAP_TAX_AREA="$2"; CAP_TAX_TOPIC="$3"; CAP_TAX_SOURCE_KIND="$4"
}

# URL·도메인·제목·설명에서 재현 가능한 규칙만 쓴다. URL 하나만 보고 "AI"
# 나 "디자인"처럼 추측하지는 않지만, 개발자가 자주 저장하는 서비스와 명확한
# 제목 키워드는 자료실의 실제 폴더까지 바로 고른다.
cap_taxonomy_web() {
  local url="$1" host="$2" title="$3" description="$4" hay
  hay=$(printf '%s %s %s %s' "$url" "$host" "$title" "$description" | tr '[:upper:]' '[:lower:]')
  _cap_tax_set reference common uncategorized site
  case "$hay" in
    *lucide.dev*|*heroicons.com*|*iconify.design*|*phosphoricons.com*|*tabler.io/icons*|*fontawesome.com*)
      _cap_tax_set asset design icons site ;;
    *unsplash.com*|*pexels.com*|*undraw.co*|*freepik.com*|*lottiefiles.com*|*illustration*|*stock-image*)
      _cap_tax_set asset design images-illustrations site ;;
    *land-book.com*|*lapa.ninja*|*awwwards.com*|*godly.website*|*landingfolio.com*|*landing-page*)
      _cap_tax_set inspiration design landing-references site ;;
    *dribbble.com*|*behance.net*|*mobbin.com*|*screenlane.com*)
      _cap_tax_set inspiration design ui-components community ;;
    *seed-design.io*|*design-system*|*design\ system*|*material\ design*|*human\ interface\ guidelines*)
      _cap_tax_set reference design color-design-systems official ;;
    *figma.com*|*figma.design*|*framer.com*|*sketch.com*)
      _cap_tax_set tool design design-tools site ;;
    *react.dev*|*nextjs.org/docs*|*vuejs.org*|*angular.dev*|*svelte.dev*|*developer.mozilla.org*)
      _cap_tax_set docs frontend official-docs official ;;
    *shadcn.com*|*radix-ui.com*|*mui.com*|*chakra-ui.com*|*ant.design*|*headlessui.com*)
      _cap_tax_set tool frontend ui-components site ;;
    *tailwindcss.com*|*css-tricks.com*|*animate.style*|*motion.dev*|*framer.com/motion*)
      _cap_tax_set reference frontend css-animation site ;;
    *search.google.com/search-console*|*google\ search\ console*|*seo*|*core\ web\ vitals*|*web\ performance*)
      _cap_tax_set tool frontend seo-performance site ;;
    *w3.org*|*web.dev/accessibility*|*a11yproject.com*|*accessibility*)
      _cap_tax_set docs frontend accessibility official ;;
    *nodejs.org*|*expressjs.com*|*fastify.dev*|*nestjs.com*|*django.*|*rubyonrails.org*)
      _cap_tax_set docs backend official-docs official ;;
    *prisma.io*|*postgresql.org*|*mongodb.com/docs*|*redis.io/docs*|*supabase.com/docs*|*database*)
      _cap_tax_set docs backend database official ;;
    *stripe.com/docs*|*auth0.com/docs*|*clerk.com/docs*|*firebase.google.com/docs/auth*|*oauth*|*authentication*)
      _cap_tax_set docs backend auth-payments official ;;
    *swagger.io*|*postman.com*|*insomnia.rest*|*/api/*|*api-reference*)
      _cap_tax_set reference backend api site ;;
    *kubernetes.io*|*docs.docker.com*|*aws.amazon.com*|*cloud.google.com*|*azure.microsoft.com*|*terraform.io*)
      _cap_tax_set docs infra official-docs official ;;
    *vercel.com/docs*|*netlify.com*|*railway.app*|*render.com*|*deployment*|*ci/cd*)
      _cap_tax_set tool infra deploy-operations site ;;
    *grafana.com*|*sentry.io*|*datadoghq.com*|*newrelic.com*|*monitoring*|*observability*)
      _cap_tax_set tool infra monitoring site ;;
    *data.go.kr*|*kaggle.com/datasets*|*dataset*|*open\ data*|*공공데이터*)
      _cap_tax_set reference data-ai data-sources official ;;
    *platform.openai.com*|*docs.anthropic.com*|*huggingface.co/docs*|*pytorch.org/docs*|*tensorflow.org*)
      _cap_tax_set docs data-ai official-docs official ;;
    *huggingface.co*|*replicate.com*|*langchain.com*|*llamaindex.ai*|*model*|*llm*)
      _cap_tax_set tool data-ai models-tools site ;;
    *prompt*|*cookbook.openai.com*)
      _cap_tax_set reference data-ai prompts-examples site ;;
    *docs.github.com*)
      _cap_tax_set docs common documentation official ;;
    *github.com*|*gitlab.com*)
      _cap_tax_set reference common github-open-source community ;;
    *programmers.co.kr*|*leetcode.com*|*hackerrank.com*|*codewars.com*|*coding\ test*|*algorithm\ problem*|*코딩테스트*)
      _cap_tax_set reference common coding-practice community ;;
    *npmjs.com*|*pypi.org*|*crates.io*|*brew.sh*|*developer-tool*|*devtool*)
      _cap_tax_set tool common developer-tools site ;;
    *owasp.org*|*security*|*cve.*)
      _cap_tax_set reference common security site ;;
    *notion.so*|*linear.app*|*atlassian.com*|*productivity*|*career*)
      _cap_tax_set tool common productivity-career site ;;
    *docs*|*documentation*)
      _cap_tax_set docs common documentation site ;;
    *blog*|*news*|*article*|*/read/*)
      _cap_tax_set article common articles site ;;
  esac
  CAP_TAX_TAGS="[\"type/$CAP_TAX_TYPE\", \"area/$CAP_TAX_AREA\", \"topic/$CAP_TAX_TOPIC\", \"source/$host\"]"
}

# 실제 폴더는 사람이 읽기 쉬운 이름을 쓴다. 이 매핑 외의 분류값은 절대
# 경로로 쓰지 않는다. 입력값이 파일 경로가 되는 통로를 만들지 않기 위해서다.
cap_taxonomy_folder() {
  local key="$1/$2"
  case "$key" in
    frontend/official-docs)       L '개발/프론트엔드/공식문서' 'Development/Frontend/Official Docs' ;;
    frontend/ui-components)       L '개발/프론트엔드/UI-컴포넌트' 'Development/Frontend/UI Components' ;;
    frontend/css-animation)       L '개발/프론트엔드/CSS-애니메이션' 'Development/Frontend/CSS and Animation' ;;
    frontend/accessibility)       L '개발/프론트엔드/접근성' 'Development/Frontend/Accessibility' ;;
    frontend/seo-performance)     L '개발/프론트엔드/SEO-성능' 'Development/Frontend/SEO and Performance' ;;
    backend/official-docs)        L '개발/백엔드/공식문서' 'Development/Backend/Official Docs' ;;
    backend/api)                  L '개발/백엔드/API' 'Development/Backend/API' ;;
    backend/database)             L '개발/백엔드/데이터베이스' 'Development/Backend/Database' ;;
    backend/auth-payments)        L '개발/백엔드/인증-결제' 'Development/Backend/Auth and Payments' ;;
    infra/official-docs)          L '개발/인프라-DevOps/공식문서' 'Development/Infra and DevOps/Official Docs' ;;
    infra/deploy-operations)      L '개발/인프라-DevOps/배포-운영' 'Development/Infra and DevOps/Deploy and Operations' ;;
    infra/monitoring)             L '개발/인프라-DevOps/모니터링' 'Development/Infra and DevOps/Monitoring' ;;
    data-ai/official-docs)        L '개발/데이터-AI/공식문서' 'Development/Data and AI/Official Docs' ;;
    data-ai/models-tools)         L '개발/데이터-AI/모델-도구' 'Development/Data and AI/Models and Tools' ;;
    data-ai/prompts-examples)     L '개발/데이터-AI/프롬프트-사례' 'Development/Data and AI/Prompts and Examples' ;;
    data-ai/data-sources)         L '개발/데이터-AI/데이터소스' 'Development/Data and AI/Data Sources' ;;
    design/icons)                 L '디자인/아이콘' 'Design/Icons' ;;
    design/images-illustrations)  L '디자인/이미지-일러스트' 'Design/Images and Illustrations' ;;
    design/landing-references)    L '디자인/랜딩페이지-레퍼런스' 'Design/Landing References' ;;
    design/ui-components)         L '디자인/UI-컴포넌트' 'Design/UI Components' ;;
    design/typography)            L '디자인/타이포그래피' 'Design/Typography' ;;
    design/color-design-systems)  L '디자인/컬러-디자인시스템' 'Design/Color and Design Systems' ;;
    design/design-tools)          L '디자인/디자인도구' 'Design/Design Tools' ;;
    common/developer-tools)       L '공통/개발도구' 'Common/Developer Tools' ;;
    common/github-open-source)    L '공통/GitHub-오픈소스' 'Common/GitHub and Open Source' ;;
    common/productivity-career)   L '공통/생산성-커리어' 'Common/Productivity and Career' ;;
    common/security)              L '공통/보안' 'Common/Security' ;;
    common/documentation)         L '공통/문서-레퍼런스' 'Common/Documentation and Reference' ;;
    common/articles)              L '공통/아티클' 'Common/Articles' ;;
    common/coding-practice)       L '공통/코딩테스트-연습' 'Common/Coding Practice' ;;
    *)                            L '공통/미분류' 'Common/Uncategorized' ;;
  esac
}
