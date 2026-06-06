from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from backend.paths import TEMPLATES_DIR
from backend.services.watch_service import watch_service

router = APIRouter()
templates = Jinja2Templates(directory=str(TEMPLATES_DIR))


@router.get("/", response_class=HTMLResponse)
async def index(request: Request) -> HTMLResponse:
    content = watch_service.get_content()
    path = watch_service.get_path()
    if content is None or path is None:
        return templates.TemplateResponse(request, "welcome.html")
    return templates.TemplateResponse(
        request,
        "viewer.html",
        {"content": content},
    )
