# 0046 - file and time of big plain section mappings (diagnostic)

After 0045 Black Ops 3 passes its module lookup and calls NtCreateSection/NtMapViewOfSection; its thread then sits in `virtual_map_section` -> memmove (map_file_into_view_ex copying the file) at ~0% CPU for over 35 s with small disk reads. `build/ntdll-unix/virtual_ios.c`: for non-image sections of 4 MB or more, `[map-sec] 0046 begin size= offset= vprot= file=<path>` and `[map-sec] 0046 done res= in N ms`. Logging only.
