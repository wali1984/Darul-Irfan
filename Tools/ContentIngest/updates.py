"""Current official notices and event reports; classification follows URL sections only."""
from datetime import datetime
from urllib.parse import urljoin, urlparse
import re
from bs4 import BeautifulSoup
import schema

SECTIONS = {'press-releases':'press-release', 'announcements':'announcement', 'seminars':'seminar', 'tv-interviews':'tv-interview'}

def detail_links(html, page_url, section):
    soup = BeautifulSoup(html, 'html.parser')
    result = []
    for link in soup.select('a[href]'):
        url = urljoin(page_url, link['href'])
        parsed = urlparse(url)
        if parsed.netloc == urlparse(page_url).netloc and re.fullmatch(r'/' + re.escape(section) + r'/\d+/[^/]+\.html', parsed.path) and url not in result:
            result.append(url)
    return result

def parse_update(html, url, rights_status, include_body):
    soup = BeautifulSoup(html, 'html.parser')
    main = soup.select_one('.c-layout-sidebar-content')
    if main is None or main.find('h1') is None:
        raise ValueError('Official update layout is missing')
    heading = main.find('h1')
    author_node = heading.select_one('.by-author')
    author = author_node.get_text(' ', strip=True) if author_node else None
    if author_node: author_node.extract()
    title = heading.get_text(' ', strip=True)
    urdu_node = main.select_one('.listing-urdu-heading')
    urdu = urdu_node.get_text(' ', strip=True) if urdu_node else None
    date_node = main.select_one('.icon-calendar + span')
    date = None
    if date_node:
        date = datetime.strptime(date_node.get_text(strip=True), '%d-%m-%Y').strftime('%Y-%m-%dT00:00:00Z')
    venue_node = main.select_one('.icon-pointer + span')
    venue = venue_node.get_text(' ', strip=True) if venue_node else None
    paragraphs = []
    for block in main.select(':scope > div.margin-top-25'):
        if re.search(r'font-size\s*:\s*3px', block.get('style','')): continue
        for junk in block.select('script,style'): junk.decompose()
        text = '\n'.join(line.strip() for line in block.get_text('\n').splitlines() if line.strip())
        if text: paragraphs.append(text)
    body = '\n'.join(paragraphs) or None
    images = list(dict.fromkeys(urljoin(url,img['src']) for img in main.select('img[src]')
        if urlparse(urljoin(url,img['src'])).netloc == urlparse(url).netloc and '/uploads/' in urlparse(urljoin(url,img['src'])).path))
    section = urlparse(url).path.split('/')[1]
    if section == 'seminar':
        # The source provides a civil date, not a clock time. Never invent an exact event time.
        event = schema.CommunityEvent(id=schema.slug_from_url(url),kind='other',title=title,title_urdu=urdu,
            details=body if include_body else None,start_date=date,dates_are_approximate=True,venue=venue,source_url=url)
        return 'events', event.to_dict()
    if section == 'tv-interview':
        video = main.select_one('[data-linktype="youtube"][data-link]')
        if video is None: return None, None
        match = re.search(r'/embed/([\w-]{11})(?:\?|$)',video['data-link'])
        if not match: return None, None
        return 'media', schema.MediaItem(id=schema.slug_from_url(url),title=title,language='ur',media_type='youtube',
            source_url=url,category='videoLectures',rights_status=rights_status,speaker=author,date=date,youtube_id=match[1]).to_dict()
    content_type, category = ('pressRelease','pressReleases') if section == 'press-release' else ('announcement','announcements')
    return 'articles', schema.ContentItem(id=schema.slug_from_url(url),source_url=url,type=content_type,title=title,
        title_urdu=urdu,language='ur' if urdu else 'en',category=category,rights_status=rights_status,author=author,
        body_plain_text=body if include_body else None,published_at=date,media_urls=images).to_dict()

def crawl_updates(fetcher, base_url, rights_status, include_body):
    payload = {'articles':[], 'events':[], 'media':[]}
    seen = set()
    warnings = []
    for index, section in SECTIONS.items():
        # A rolling three-page window catches late-posted reports without re-downloading the archive.
        for page in range(1,4):
            if fetcher.cap_reached: break
            index_url = base_url + '/' + index + ('' if page == 1 else '/page/' + str(page))
            html = fetcher.fetch(index_url)
            if html is None: continue
            for url in detail_links(html,index_url,section):
                if url in seen or fetcher.cap_reached: continue
                seen.add(url)
                detail = fetcher.fetch(url)
                if detail is None: continue
                try:
                    group, item = parse_update(detail,url,rights_status,include_body)
                    if item: payload[group].append(item)
                    else: warnings.append(url + ': no supported native video; retained on source site.')
                except ValueError as error:
                    warnings.append(url + ': ' + str(error))
    return payload, warnings
