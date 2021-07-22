package org.bu.jenkins.util;

/**
 * Path converter between linux and windows. Will convert a windows path (ie: "C:\path\to\file")
 * to a linux path (ie: "/c/path/to/file") and vice-versa.
 * 
 * @author wrh
 *
 */
public class Path {
	
	public static boolean isWindows = System.getProperty("os.name")
			  .toLowerCase().startsWith("windows");
	
	public static final String WINDOWS_SEPARATOR = "\\";
	public static final String LINUX_SEPARATOR = "/";

	private String path;

	public Path(String path) {
		this.path = path;
	}

	private boolean resemblesLinux() {
		return path.contains(LINUX_SEPARATOR) && ! path.contains(WINDOWS_SEPARATOR);
	}
	
	/**
	 * Get the directory/fil path as a linux path.
	 * @param wsl Windows Subsystem for Linux (WSL). When called directly, bash will "see" /c/ at /mnt/c/.
	 * @return
	 */
	public String toLinux(boolean wsl) {
		if(resemblesWindows()) {
			String[] parts = path.split(WINDOWS_SEPARATOR + WINDOWS_SEPARATOR);
			String driveletter = parts[0];
			if(driveletter.endsWith(":")) {
				driveletter = driveletter.replace(":", "");
			}
			driveletter = "/" + driveletter.toLowerCase();
			if(wsl) {
				driveletter = "/mnt" + driveletter;
			}
			StringBuilder linuxPath = new StringBuilder(driveletter);
			for(int i=1; i<parts.length; i++) {
				linuxPath.append(LINUX_SEPARATOR).append(parts[i]);
			}
			return linuxPath.toString();
		}
		return path;
	}
	
	private boolean resemblesWindows() {
		return path.contains(WINDOWS_SEPARATOR) && ! path.contains(LINUX_SEPARATOR);
	}
	
	public String toWindows() {
		if(resemblesLinux()) {
			String[] parts = path.split(LINUX_SEPARATOR);
			String driveletter = parts[0];
			int startIndex = 1;
			if(driveletter.isBlank()) {
				driveletter = parts[1];
				startIndex++;
			}
			driveletter = driveletter + ":";
			StringBuilder windowsPath = new StringBuilder(driveletter);
			for(int i=startIndex; i<parts.length; i++) {
				windowsPath.append(WINDOWS_SEPARATOR).append(parts[i]);
			}
			return windowsPath.toString();
		}
		return path;
	}
	
	public static void main(String[] args) {
		Path path = new Path("C:\\Users\\wrh\\.ssh\\mykey");
		System.out.println(path.toLinux(true));
		
		path = new Path("/c/Users/wrh/.ssh/mykey");
		System.out.println(path.toWindows());
		
	}
}
