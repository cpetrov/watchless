#!/bin/sh
ver=0.1.0

#-----------------------------------------------------------------------#
#
# watchless
#   
# Watches for LESS file changes in the specified directory using inotifywait
# and compiles those files to CSS. Supports imported files.
#  Christian Petrov <Christian.Petrov@outlook.com>
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#-----------------------------------------------------------------------#

echo_help() 
{
	echo "Usage: watchless [OPTION] [DIR]"
	echo "  Where DIR is the directory containing your LESS files, which"
	echo "  may contain included files."
	echo "  -h        Display this help and exit."
	echo "  -v        Display version number and exit."
	echo "  -k        Keeps directory structure intact, for example"
	echo "            ~/Project/less/main.less will be compiled to "
	echo "            ~/Project/css/main.css. Without the -k option"
	echo "            CSS files will be created in the same directory"
	echo "            as the LESS file."
	echo "  Example: watchless -k ~/Project/less"
	exit 0
}

echo_version() 
{
	echo "Version: "$ver
	exit 0
}

keepDirStructure=false
while getopts ":khv" opt; do
	case $opt in
		k)
			keepDirStructure=true
			;;
		h)
			echo_help
			;;
		v)
			echo_version
			;;
		\?)
			echo "Invalid option: -$OPTARG"
			exit 1
			;;
	esac
done
shift $(( ${OPTIND} - 1 ));

if [[ -n "$1" ]]
	then 
	lessDir=$1
	childrenPath=
	parents=
	if [ -d "$lessDir" ]
		then
		all=$(find $lessDir -maxdepth 1 -type f | grep less)
		allArr=( $all )
		echo "Watching $1 for LESS file modifications."
		if [ ! -z "$all" ]
			then
			filesCount=0
			for lessFile in "${allArr[@]}"
			do
				let "filesCount+=1"
				content=$(cat "$lessFile" | grep @import)
				if [[ "$content" == *@* ]]
					then
					childName[$filesCount]=$(echo $content | sed 's/@import//g;s/ //g;s/"//g;s/;/,/g')
					IFS=',' read -a childrenNames <<< "${childName[$filesCount]}"

					childrenCount=0
					for childName in "${childrenNames[@]}"
					do
						i=0
						inclArr=
						while [ $i -lt ${#childName} ]
						do
							inclArr[$i]=${childName:$i:1}
							i=$((i+1))
						done

						dotSegments=0
						nonDotReached=false
						for z in "${inclArr[@]}"
						do
							if [ "$z" == "." ] && ! $nonDotReached 
							then 
								dotSegments=$((dotSegments+1))
							elif [ "$z" != "." ]
							then
								nonDotReached=true
							fi
						done

						childName=$(sed -r "s/^.{$dotSegments}//;s/^\///" <<< $childName)
						_childPath=$1 #to sed

						slashes="${_childPath//[^\/]}"
						slashesCount="${#slashes}"
						slashesToKeep=$(($slashesCount-$dotSegments))

						n=$((3+$slashesToKeep))

						_childPath=$(sed "s/[^/]*//$n;s/\/\/.*//g" <<< $_childPath)
						_childPath=${_childPath%/}
						parents[$childrenCount]=$lessFile
						children[$childrenCount]=$_childPath/$childName

						childrenPath[$childrenCount]=$(echo ${children[$childrenCount]} | sed "s/\/[^\/]*$//")

						let "childrenCount+=1"
					done
				fi

			done
			childrenPath+=($1)
			paths=$(echo ${childrenPath[@]} | sed "s/ /\n/g" | sort | uniq)

			while true 
			do
				inotifywait -qe modify --format '%w%f' $paths | while read modifiedFile
				do  
				count=0
				fileIsIncluded=false
				for child in "${children[@]}"
				do
					if [[ "$child" == "$modifiedFile" ]]
						then

						cssFile=${parents[$count]}

						if $keepDirStructure
							then
							cssFile=$(sed 's/\/less\//\/css\//g' <<< $cssFile)
						fi

						cssFile=$(sed 's/\.less/\.css/g' <<< $cssFile)
						echo -e "\nCompiling parent of modified file \n $modifiedFile \nto:\n \e[1;32m"$cssFile"\e[00m"
						lessc --verbose ${parents[$count]} > $cssFile
						fileIsIncluded=true
						break
					fi
					let "count+=1"
				done

				if [[ $fileIsIncluded == false ]]
					then
					for parent in "${parents[@]}"
					do
						if [[ "$parent" == "$modifiedFile" ]]
							then

							cssFile=$modifiedFile

							if $keepDirStructure
								then
								cssFile=$(sed 's/\/less\//\/css\//g' <<< $cssFile)
							fi

							cssFile=$(sed 's/\.less/\.css/g' <<< $cssFile)
							echo -e "\nCompiling modified file \n $modifiedFile \nto:\n \e[1;32m"$cssFile"\e[00m"
							lessc --verbose $modifiedFile > $cssFile
							break
						fi
					done

				fi
				done

			done

		else
			echo "No less files found in the specified directory." ; exit 1
		fi
	else
		echo "Specified directory doesn't exist." ; exit 1
	fi
else
	echo "Less directory path not given. Usage: watchless [OPTION] [DIR]" ; exit 1
fi
