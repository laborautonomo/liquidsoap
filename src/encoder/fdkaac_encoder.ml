(*****************************************************************************
  
  Liquidsoap, a programmable audio stream generator.
  Copyright 2003-2017 Savonet team
  
  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.
  
  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details, fully stated in the COPYING
  file at the root of the liquidsoap distribution.
  
  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
  
 *****************************************************************************)
  
(** FDK-AAC encoder *)

module type Fdkaac_t =
  sig
    module Encoder :
      sig
        exception Invalid_handle
        exception Unsupported_parameter
        exception Invalid_config
        exception Error of int
        exception End_of_file
        exception Unknown of int
        val string_of_exception : exn -> string option
        type t
        type mpeg2_aac = [ `AAC_LC | `HE_AAC | `HE_AAC_v2 ]
        type mpeg4_aac =
            [ `AAC_ELD | `AAC_LC | `AAC_LD | `HE_AAC | `HE_AAC_v2 ]
        type aot = [ `Mpeg_2 of mpeg2_aac | `Mpeg_4 of mpeg4_aac ]
        type bitrate_mode = [ `Constant | `Variable of int | `Full_bitreservoir ]
        type transmux =
            [ `Adif | `Adts | `Latm | `Latm_out_of_band | `Loas | `Raw ]
        type param_name =
            [ `Afterburner
            | `Aot
            | `Bandwidth
            | `Bitrate
            | `Bitrate_mode
            | `Granule_length
            | `Samplerate
            | `Sbr_mode
            | `Transmux ]
        type param =
            [ `Afterburner of bool
            | `Aot of aot
            | `Bandwidth of bool
            | `Bitrate of int
            | `Bitrate_mode of bitrate_mode
            | `Granule_length of int
            | `Samplerate of int
            | `Sbr_mode of bool
            | `Transmux of transmux ]
        val create : int -> t
        val set : t -> param -> unit
        val get : t -> param_name -> param
        val encode : t -> string -> int -> int -> string
        val flush : t -> string
      end
  end
  
module Register(Fdkaac : Fdkaac_t) =
struct
  module G = Generator.Generator
  
  let create_encoder params =
    let encoder =
      Fdkaac.Encoder.create params.Fdkaac_format.channels
    in
    let params = [
      `Aot params.Fdkaac_format.aot;
      `Samplerate params.Fdkaac_format.samplerate;
      `Transmux params.Fdkaac_format.transmux;
      `Afterburner params.Fdkaac_format.afterburner;
    ] @ (
        if params.Fdkaac_format.aot = `Mpeg_4 `AAC_ELD then
          [`Sbr_mode params.Fdkaac_format.sbr_mode]
        else [])
      @ (
        match params.Fdkaac_format.bitrate_mode with
          | `Variable vbr -> [`Bitrate_mode (`Variable vbr)]
          | `Constant     -> [`Bitrate (params.Fdkaac_format.bitrate*1000)])
    in
    List.iter (Fdkaac.Encoder.set encoder) params;
    encoder
  
  let encoder aac =
    let enc = create_encoder aac in
    let channels = aac.Fdkaac_format.channels in
    let samplerate = aac.Fdkaac_format.samplerate in
    let samplerate_converter =
      Audio_converter.Samplerate.create channels
    in
    let src_freq = float (Frame.audio_of_seconds 1.) in
    let dst_freq = float samplerate in
    let n = 1024 in
    let buf = Buffer.create n in
    let encode frame start len =
      let start = Frame.audio_of_master start in
      let b = AFrame.content_of_type ~channels frame start in
      let len = Frame.audio_of_master len in
      let b,start,len =
        if src_freq <> dst_freq then
          let b = Audio_converter.Samplerate.resample
            samplerate_converter (dst_freq /. src_freq)
            b start len
          in
          b,0,Array.length b.(0)
        else
          b,start,len
      in
      let encoded = Buffer.create n in
      Buffer.add_string buf (Audio.S16LE.make b start len);
      let len = Buffer.length buf in
      let rec f start =
        if start+n > len then
         begin
          Utils.buffer_drop buf start;
          Buffer.contents encoded
         end
        else
         begin
          let data = Buffer.sub buf start n in
          Buffer.add_string encoded
            (Fdkaac.Encoder.encode enc data 0 n);
          f (start+n)
        end
      in
      f 0
    in
    let stop () =
      let rem = Buffer.contents buf in
      let s =
        Fdkaac.Encoder.encode enc rem 0 (String.length rem)
      in
      s ^ (Fdkaac.Encoder.flush enc)
    in
      {
        Encoder.
         insert_metadata = (fun _ -> ()) ;
         header = None ;
         encode = encode ;
         stop = stop
      }
  
  let register_encoder name =
    Encoder.plug#register name
      (function
         | Encoder.FdkAacEnc m -> Some (fun _ _ -> encoder m)
         | _ -> None)
end
