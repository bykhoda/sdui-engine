import Foundation

/// Inline copies of `spec/examples/*.json` so tests stay hermetic and don't
/// depend on bundle resource paths. Keep in sync with the spec examples.
enum Fixtures {
    static let productDetail = """
    {
      "version": "0.1",
      "screen": {
        "id": "product_detail",
        "title": "$data.product.title",
        "analytics": { "screenName": "product.detail" },
        "data": {
          "mode": "parallel",
          "sources": [
            { "id": "product", "service": "catalog", "path": "/products/{productId}",
              "method": "GET", "query": { "lang": "$env.locale" }, "policy": "cacheThenNetwork" }
          ]
        },
        "refresh": { "sources": ["product"] },
        "content": {
          "type": "scroll",
          "axis": "vertical",
          "child": {
            "type": "vstack",
            "spacing": "$token.spacing.md",
            "children": [
              { "type": "image", "source": "$data.product.imageUrl",
                "loader": { "placeholder": "skeleton", "aspectRatio": 1.6 } },
              { "type": "text", "value": "$data.product.title", "style": "$token.typography.title2" },
              { "type": "button", "title": "Купить", "style": "$token.button.primary",
                "onTap": { "action": "navigate", "to": "checkout",
                           "params": { "productId": "$data.product.id" }, "transition": "sheet" } }
            ]
          }
        }
      }
    }
    """

    static let feed = """
    {
      "version": "0.1",
      "screen": {
        "id": "feed",
        "title": "Лента",
        "content": {
          "type": "list",
          "items": "$data.feed.items",
          "spacing": "$token.spacing.md",
          "template": {
            "type": "vstack",
            "modifiers": {
              "onTap": { "action": "navigate", "to": "product_detail",
                         "params": { "productId": "$item.id" } },
              "contextMenu": [
                { "title": "Поделиться", "action": { "action": "share", "url": "$item.shareUrl" } },
                { "title": "Скрыть", "role": "destructive",
                  "action": { "action": "custom", "name": "hideItem", "payload": { "id": "$item.id" } } }
              ]
            },
            "children": [
              { "type": "text", "value": "$item.title", "style": "$token.typography.headline" }
            ]
          }
        }
      }
    }
    """
}
