# aks

A RAW image editor. You may call it Viberoom.

<div align="center"><img width="800" height="1600" alt="image" src="https://github.com/user-attachments/assets/ad1a87f7-41e4-454a-874d-4e4708c108ed" /></div>

Very minimal for now but it has most basic RAW editing features (crop, white balance, colour curves and so on).

Linux only for now but hey, give it some time. The flatpak should work and it has GPU acceleration via vulkan if your machine is good enough.

# running it

Install the flatpak, or:

```
flutter run -d linux
```

It has a few requirements which you will notice as it won't run otherwise (libraw, vulkan headers, etc.).

# on the flatpak (important)

It has full home dir access. You can tighten this if you want, it'll change in the near future. Regardless, it has no network access and generally no harmful permissions.

One thing to note though is that the build isn't fully reproducible as it requires the vulkan-related stuff to be built beforehand and bundled, which is what I do at the moment. This will also change but it's not a big deal for now so I didn't care much.
