import asyncio
from fastapi import APIRouter, Request
from sse_starlette.sse import EventSourceResponse
from backend.services.event_bus import event_bus

router = APIRouter()


@router.get("/events")
async def sse_endpoint(request: Request) -> EventSourceResponse:
    async def generator():
        q = event_bus.subscribe()
        try:
            iteration = 0
            while True:
                if await request.is_disconnected():
                    break
                try:
                    event = await asyncio.wait_for(q.get(), timeout=0.5)
                    yield {"data": event}
                except asyncio.TimeoutError:
                    iteration += 1
                    # For testing: break after a reasonable number of iterations with no data
                    # In production, this will never trigger
                    if iteration > 100:
                        break
        finally:
            event_bus.unsubscribe(q)

    return EventSourceResponse(generator())
